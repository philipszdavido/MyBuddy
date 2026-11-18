//
//  FirebaseMediaRepository.swift
//
//  Paths (see MediaPath): chat_images/{uid}/{messageId}.jpg, avatars/{uid}/{uuid}.jpg
//  Legacy Cloudinary and `images/` URLs stored in old messages keep working for display.
//

import Foundation
import FirebaseStorage

final class FirebaseMediaRepository: MediaRepository, @unchecked Sendable {
    private let storage: Storage
    init(storage: Storage = Storage.storage()) { self.storage = storage }

    func uploadImage(_ data: Data, path: String, onProgress: (@Sendable (Double) -> Void)?) async throws -> UploadedMedia {
        let ref = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.cacheControl = "public, max-age=31536000"   // paths are immutable per upload
        do {
            _ = try await ref.putDataAsync(data, metadata: metadata) { progress in
                if let progress { onProgress?(progress.fractionCompleted) }
            }
            return UploadedMedia(id: path, url: try await ref.downloadURL().absoluteString)
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    func delete(url: String) async throws {
        // `reference(forURL:)` can trap on foreign URLs, so only pass Firebase Storage hosts.
        guard let host = URL(string: url)?.host, host.hasSuffix("firebasestorage.googleapis.com") else { return }
        do { try await storage.reference(forURL: url).delete() }
        catch { throw FirebaseErrorMapper.map(error) }
    }
}
