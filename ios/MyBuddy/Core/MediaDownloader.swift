//
//  MediaDownloader.swift
//

import Foundation

enum MediaDownloader {
    static let maxBytes = 25 * 1024 * 1024

    /// HTTPS only, status-checked, size-bounded, cancellable (async URLSession).
    static func data(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            throw AppError.validation("Invalid media URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AppError.backend(underlying: "media http status")
            }
            guard data.count <= maxBytes else { throw AppError.storage(underlying: "media too large") }
            return data
        } catch { throw AppError.wrap(error) }
    }
}
