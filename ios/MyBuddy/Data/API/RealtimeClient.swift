//
//  RealtimeClient.swift
//  MyBuddy
//
//  Minimal Socket.IO (protocol v5 over Engine.IO v4, WebSocket transport only) client for the
//  MyBuddy API's /realtime namespace, built on URLSessionWebSocketTask so the app needs no extra
//  package. Supports: namespace connect with auth, events, acks, server pings, reconnect with
//  exponential backoff. Delivery is best-effort by design: after every (re)connect subscribers get
//  `.connected` and re-sync from REST (PostgreSQL is the source of truth).
//

import Foundation

enum RealtimeSignal: Sendable {
    case connected
    case disconnected
    case event(name: String, payload: Data)
}

final class RealtimeClient: NSObject, @unchecked Sendable, URLSessionWebSocketDelegate {
    private let baseURL: URL
    private let namespace = "/realtime"
    private let tokenProvider: @Sendable (Bool) async throws -> String
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var subscribers: [UUID: AsyncStream<RealtimeSignal>.Continuation] = [:]
    private var acks: [Int: CheckedContinuation<Data, Error>] = [:]
    private var nextAck = 0
    private var namespaceReady = false
    private var running = false
    private var attempt = 0
    private var refreshTimer: Task<Void, Never>?

    init(baseURL: URL, tokenProvider: @escaping @Sendable (Bool) async throws -> String) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: Public API

    /// Signals for every event plus connection changes. Connecting starts with the first subscriber
    /// and stops when the last one goes away.
    func signals() -> AsyncStream<RealtimeSignal> {
        AsyncStream { continuation in
            let id = UUID()
            let (start, alreadyConnected) = lock.withLock { () -> (Bool, Bool) in
                subscribers[id] = continuation
                let start = !running
                running = true
                return (start, namespaceReady)
            }
            if alreadyConnected { continuation.yield(.connected) }
            if start { connect() }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                let stop = self.lock.withLock { () -> Bool in
                    self.subscribers.removeValue(forKey: id)
                    if self.subscribers.isEmpty { self.running = false; return true }
                    return false
                }
                if stop { self.close() }
            }
        }
    }

    /// Emits an event and waits for the server's acknowledgement payload (first ack argument).
    func emitWithAck(_ event: String, _ payload: [String: Any], timeout: TimeInterval = 10) async throws -> Data {
        let (id, ready) = lock.withLock { () -> (Int, Bool) in
            nextAck += 1
            return (nextAck, namespaceReady)
        }
        guard ready else { throw AppError.network(underlying: "realtime not connected") }
        let body = try JSONSerialization.data(withJSONObject: [event, payload])
        let frame = "42\(namespace),\(id)" + String(decoding: body, as: UTF8.self)
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
                    self.lock.withLock { self.acks[id] = c }
                    self.write(frame)
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw AppError.network(underlying: "realtime ack timeout")
            }
            defer { group.cancelAll() }
            let result = try await group.next()!
            return result
        }
    }

    /// Fire-and-forget event (typing indicators, read receipts).
    func emit(_ event: String, _ payload: [String: Any]) {
        guard lock.withLock({ namespaceReady }),
              let body = try? JSONSerialization.data(withJSONObject: [event, payload]) else { return }
        write("42\(namespace)," + String(decoding: body, as: UTF8.self))
    }

    // MARK: Connection

    private func socketURL() -> URL {
        var c = URLComponents(url: baseURL.appending(path: "socket.io/"), resolvingAgainstBaseURL: false)!
        c.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        c.queryItems = [URLQueryItem(name: "EIO", value: "4"), URLQueryItem(name: "transport", value: "websocket")]
        return c.url!
    }

    private func connect() {
        guard lock.withLock({ running }) else { return }
        let task = session.webSocketTask(with: socketURL())
        lock.withLock { self.task = task; namespaceReady = false }
        task.resume()
        receive(on: task)
    }

    private func close() {
        let (task, pending) = lock.withLock { () -> (URLSessionWebSocketTask?, [CheckedContinuation<Data, Error>]) in
            let t = self.task
            self.task = nil
            namespaceReady = false
            let p = Array(acks.values)
            acks.removeAll()
            return (t, p)
        }
        refreshTimer?.cancel()
        pending.forEach { $0.resume(throwing: AppError.network(underlying: "realtime closed")) }
        task?.cancel(with: .goingAway, reason: nil)
    }

    private func scheduleReconnect() {
        let (shouldRetry, delay) = lock.withLock { () -> (Bool, Double) in
            namespaceReady = false
            attempt += 1
            return (running, min(30, pow(2, Double(min(attempt, 5)))) + Double.random(in: 0...1))
        }
        broadcast(.disconnected)
        let pending = lock.withLock { () -> [CheckedContinuation<Data, Error>] in
            let p = Array(acks.values); acks.removeAll(); return p
        }
        pending.forEach { $0.resume(throwing: AppError.network(underlying: "realtime disconnected")) }
        guard shouldRetry else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.connect()
        }
    }

    private func write(_ text: String) {
        lock.withLock { task }?.send(.string(text)) { _ in }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, self.lock.withLock({ self.task === task }) else { return }
            switch result {
            case .failure:
                self.scheduleReconnect()
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                self.receive(on: task)
            }
        }
    }

    // MARK: Protocol

    private func handle(_ packet: String) {
        guard let type = packet.first else { return }
        switch type {
        case "0": // Engine.IO open → connect to namespace with auth
            Task { [weak self] in
                guard let self else { return }
                do {
                    let token = try await self.tokenProvider(false)
                    let auth = try JSONSerialization.data(withJSONObject: ["token": token])
                    self.write("40\(self.namespace)," + String(decoding: auth, as: UTF8.self))
                } catch {
                    self.scheduleReconnect()
                }
            }
        case "2": write("3") // ping → pong
        case "1": scheduleReconnect() // server closed
        case "4": handleSocketIO(String(packet.dropFirst()))
        default: break
        }
    }

    private func handleSocketIO(_ body: String) {
        guard let kind = body.first else { return }
        var rest = Substring(body.dropFirst())
        if rest.hasPrefix(namespace) {
            rest = rest.dropFirst(namespace.count)
            if rest.first == "," { rest = rest.dropFirst() }
        }
        switch kind {
        case "0": // namespace connected
            lock.withLock { namespaceReady = true; attempt = 0 }
            broadcast(.connected)
            scheduleTokenRefresh()
        case "4": // connect error (bad token): refresh token before retrying
            Task { [weak self] in
                _ = try? await self?.tokenProvider(true)
                self?.scheduleReconnect()
            }
        case "1": scheduleReconnect()
        case "2": // event: [name, payload]
            let json = rest.drop(while: { $0.isNumber })
            guard let data = json.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let name = array.first as? String else { return }
            if name == "error" || name == "session:revoked" { return }
            let payload = array.count > 1 ? (try? JSONSerialization.data(withJSONObject: array[1], options: .fragmentsAllowed)) ?? Data() : Data()
            broadcast(.event(name: name, payload: payload))
        case "3": // ack: <id>[payload]
            let digits = rest.prefix(while: { $0.isNumber })
            guard let id = Int(digits) else { return }
            let json = rest.dropFirst(digits.count)
            let continuation = lock.withLock { acks.removeValue(forKey: id) }
            guard let data = json.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let first = array.first,
                  let payload = try? JSONSerialization.data(withJSONObject: first, options: .fragmentsAllowed) else {
                continuation?.resume(throwing: AppError.backend(underlying: "bad ack"))
                return
            }
            continuation?.resume(returning: payload)
        default: break
        }
    }

    /// ID tokens last an hour; hand the server a fresh one before the connection would be dropped.
    private func scheduleTokenRefresh() {
        refreshTimer?.cancel()
        refreshTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45 * 60))
            guard let self, !Task.isCancelled, let token = try? await self.tokenProvider(true) else { return }
            _ = try? await self.emitWithAck("auth:refresh", ["token": token])
            self.scheduleTokenRefresh()
        }
    }

    private func broadcast(_ signal: RealtimeSignal) {
        lock.withLock { Array(subscribers.values) }.forEach { $0.yield(signal) }
    }
}
