//
//  OutboxRetrier.swift
//  MyBuddy
//
//  Re-sends locally pending messages when the app becomes active and whenever
//  connectivity returns. Safe to run repeatedly because sends are idempotent
//  on the client-generated message id.
//

import Foundation
import Network

enum NetworkMonitor {
    /// Emits `true` whenever the network path is usable.
    static func stream() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            monitor.start(queue: DispatchQueue(label: "mybuddy.network-monitor"))
            continuation.onTermination = { _ in monitor.cancel() }
        }
    }
}

@MainActor
final class OutboxRetrier {
    static let shared = OutboxRetrier(
        repository: AppContainer.shared.chatRepository,
        media: AppContainer.shared.mediaRepository
    )

    private let repository: ChatRepository
    private let media: MediaRepository
    private let coreData = CoreDataUtils.shared
    private var userID: String?
    private var monitorTask: Task<Void, Never>?
    private var isFlushing = false
    private var flushRequested = false

    init(repository: ChatRepository, media: MediaRepository) {
        self.repository = repository
        self.media = media
    }

    /// Callable from any context (e.g. view models that are not main-actor isolated).
    nonisolated static func requestFlush() {
        Task { @MainActor in shared.flush() }
    }

    func start(userID: String?) {
        monitorTask?.cancel()
        self.userID = userID
        guard userID != nil else { return }
        monitorTask = Task { [weak self] in
            for await online in NetworkMonitor.stream() where online {
                self?.flush()
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        userID = nil
    }

    func flush() {
        guard userID != nil else { return }
        if isFlushing { flushRequested = true; return }   // pick up anything queued meanwhile
        isFlushing = true
        Task { await drain() }
    }

    private func drain() async {
        defer { isFlushing = false }
        repeat {
            flushRequested = false
            guard let uid = userID else { return }
            for item in coreData.fetchUnsentOutbox(senderId: uid) {
                do {
                    try await deliver(item)
                } catch {
                    let appError = AppError.wrap(error)
                    if case .cancelled = appError { return }
                    Log.chat.error("outbox delivery failed: \(appError.diagnostic, privacy: .public)")
                    if appError.isRetryable { break }          // keep ordering; retry on reconnect / foreground
                    // Permanent rejection (e.g. permission denied): surface "failed" with a Retry action.
                    coreData.markMessageFailed(id: item.message.id)
                }
            }
        } while flushRequested
    }

    /// Upload (if needed) then send. Both steps are idempotent: the upload path and the message id
    /// are derived from the message id, so a retry after a lost response cannot duplicate anything.
    private func deliver(_ item: OutboxItem) async throws {
        var message = item.message
        if let data = item.pendingImageData, message.mediaURL.isEmpty {
            let path = MediaPath.chatImage(userID: message.senderID, messageID: message.id)
            let uploaded = try await media.uploadImage(data, path: path, onProgress: nil)
            coreData.setMessageMediaURL(id: message.id, url: uploaded.url)
            message = message.with(media: uploaded)
        }
        try await repository.send(message)
        coreData.markMessageSent(id: message.id)
    }
}
