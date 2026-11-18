//
//  APIClient.swift
//  MyBuddy
//
//  HTTP client for the MyBuddy API (/api/v1). Every request carries a Firebase ID token; on 401 the
//  token is force-refreshed once and the request retried. Server errors arrive as
//  { "error": { "code", "message" } } and are mapped to AppError (the UI never sees raw HTTP errors).
//

import Foundation

struct APIErrorBody: Decodable {
    struct Inner: Decodable {
        let code: String
        let message: String
    }
    let error: Inner
}

/// Returned by endpoints with no meaningful body (204).
struct EmptyResponse: Decodable {}

final class APIClient: @unchecked Sendable {
    let baseURL: URL
    private let session: URLSession
    private let tokenProvider: @Sendable (_ forceRefresh: Bool) async throws -> String
    let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL, session: URLSession = .shared, tokenProvider: @escaping @Sendable (Bool) async throws -> String) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.decoder = APIClient.makeDecoder()
        self.encoder = JSONEncoder()
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            if let date = APIClient.parseDate(raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "bad date \(raw)"))
        }
        return decoder
    }

    static func parseDate(_ raw: String) -> Date? {
        if let d = try? Date(raw, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)) { return d }
        if let d = try? Date(raw, strategy: .iso8601) { return d }
        // date-only values (analytics buckets)
        return try? Date(raw, strategy: .iso8601.year().month().day())
    }

    /// The token to hand to the realtime connection.
    func currentToken(forceRefresh: Bool = false) async throws -> String { try await tokenProvider(forceRefresh) }

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try await send("GET", path, query: query, body: Optional<Int>.none)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await send("POST", path, query: [:], body: body)
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try await send("POST", path, query: [:], body: Optional<Int>.none)
    }

    func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await send("PATCH", path, query: [:], body: body)
    }

    func put<B: Encodable>(_ path: String, body: B) async throws {
        let _: EmptyResponse = try await send("PUT", path, query: [:], body: body)
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await send("DELETE", path, query: [:], body: Optional<Int>.none)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await send("DELETE", path, query: [:], body: Optional<Int>.none)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, query: [String: String?], body: B?) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: "api/v1").appending(path: path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        guard let url = components.url else { throw AppError.validation("Invalid request") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        for attempt in 0..<2 {
            request.setValue("Bearer \(try await tokenProvider(attempt > 0))", forHTTPHeaderField: "Authorization")
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw AppError.wrap(error)
            }
            guard let http = response as? HTTPURLResponse else { throw AppError.backend(underlying: "no HTTP response") }
            if http.statusCode == 401, attempt == 0 { continue } // token expired: refresh once
            if (200..<300).contains(http.statusCode) {
                if data.isEmpty || http.statusCode == 204 {
                    if let empty = EmptyResponse() as? T { return empty }
                }
                do { return try decoder.decode(T.self, from: data) }
                catch { throw AppError.backend(underlying: "decode \(T.self): \(error)") }
            }
            throw Self.map(status: http.statusCode, data: data, decoder: decoder)
        }
        throw AppError.authentication(.sessionExpired)
    }

    static func map(status: Int, data: Data, decoder: JSONDecoder) -> AppError {
        let body = try? decoder.decode(APIErrorBody.self, from: data)
        let code = body?.error.code ?? ""
        let message = body?.error.message ?? ""
        switch (status, code) {
        case (401, "TOKEN_REVOKED"), (401, _): return .authentication(.sessionExpired)
        case (403, "ACCOUNT_SUSPENDED"): return .authentication(.accountDisabled)
        case (403, _): return message.isEmpty ? .permission : .validation(message)
        case (404, _): return .notFound
        case (429, _): return .network(underlying: "rate limited")       // retryable later
        case (400..<500, _): return .validation(message.isEmpty ? AppError.unknown(underlying: "").userMessage : message)
        default: return .backend(underlying: "HTTP \(status) \(code)")
        }
    }
}
