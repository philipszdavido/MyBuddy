//
//  SettingsViewModel.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 25/07/2025.
//

import Foundation
import UIKit

@MainActor
final class SettingsViewModel: ObservableObject {

    static let shared = SettingsViewModel()

    private let media: MediaRepository
    private let users: UserRepository

    @Published var loading = false

    init(
        media: MediaRepository = AppContainer.shared.mediaRepository,
        users: UserRepository = AppContainer.shared.userRepository
    ) {
        self.media = media
        self.users = users
    }

    /// Resizes to avatar size, uploads, updates the profile, then removes the previous file (best effort).
    func editPhoto(
        userId: String,
        image: UIImage,
        replacing oldURL: String? = nil,
        completion: @escaping (String?) -> Void
    ) {
        loading = true
        Task {
            defer { loading = false }
            guard let processed = await ImageProcessor.prepare(image, maxDimension: ImageProcessor.avatarMaxDimension) else {
                completion(nil)
                return
            }
            do {
                // Unique path per upload so clients never show a stale cached avatar.
                let path = MediaPath.avatar(userID: userId, imageID: UUID().uuidString)
                let uploaded = try await media.uploadImage(processed.data, path: path, onProgress: nil)
                try await users.updatePhoto(id: userId, media: uploaded)
                completion(uploaded.url)
                if let oldURL { try? await media.delete(url: oldURL) }
            } catch {
                Log.storage.error("avatar update failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
                completion(nil)
            }
        }
    }

    /// Clears the profile photo on the server, deletes the file, then calls `completion`.
    func deletePhoto(userId: String, imageUrl: String, _ completion: @escaping () -> Void) {
        loading = true
        Task {
            defer { loading = false }
            do {
                try await users.updatePhoto(id: userId, media: nil)
                try? await media.delete(url: imageUrl)
                completion()
            } catch {
                Log.storage.error("avatar delete failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
            }
        }
    }
}
