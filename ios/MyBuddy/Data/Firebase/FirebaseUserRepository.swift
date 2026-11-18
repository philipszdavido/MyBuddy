//
//  FirebaseUserRepository.swift
//  MyBuddy
//
//  Schema preserved from the existing `users/{uid}` documents:
//  email, displayName, phoneNumber (Int64), url, createdAt (Timestamp).
//

import Foundation
import FirebaseFirestore

final class FirebaseUserRepository: UserRepository, @unchecked Sendable {
    private let db: Firestore
    /// Firestore `in` supports up to 30 values.
    private static let chunkSize = 30

    init(db: Firestore = Firestore.firestore()) { self.db = db }

    private static func account(from doc: DocumentSnapshot) -> UserAccount? {
        guard let data = doc.data() else { return nil }
        return UserAccount(
            id: doc.documentID,
            email: data["email"] as? String ?? "",
            displayName: data["displayName"] as? String ?? "",
            phoneNumber: (data["phoneNumber"] as? NSNumber)?.int64Value ?? 0,
            photoURL: data["url"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    func account(id: String) async throws -> UserAccount? {
        do {
            let doc = try await db.collection("users").document(id).getDocument()
            return doc.exists ? Self.account(from: doc) : nil
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    func save(_ account: UserAccount) async throws {
        var fields: [String: Any] = [
            "email": account.email,
            "displayName": account.displayName,
            "phoneNumber": account.phoneNumber,
            "createdAt": Timestamp(date: account.createdAt)
        ]
        if let url = account.photoURL { fields["url"] = url }
        do {
            // merge: never clobber fields this client doesn't know about
            try await db.collection("users").document(account.id).setData(fields, merge: true)
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    func updatePhoto(id: String, media: UploadedMedia?) async throws {
        let value: Any
        if let url = media?.url { value = url } else { value = FieldValue.delete() }
        do {
            try await db.collection("users").document(id).setData(["url": value], merge: true)
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    /// Firestore has no server-side contact list: a full sync is the same lookup.
    func syncContacts(phoneNumbers numbers: [Int64]) async throws -> [UserAccount] {
        try await accounts(matchingPhoneNumbers: numbers)
    }

    func accounts(matchingPhoneNumbers numbers: [Int64]) async throws -> [UserAccount] {
        let unique = Array(Set(numbers.filter { $0 > 0 }))
        guard !unique.isEmpty else { return [] }
        let chunks = stride(from: 0, to: unique.count, by: Self.chunkSize).map {
            Array(unique[$0..<min($0 + Self.chunkSize, unique.count)])
        }
        do {
            return try await withThrowingTaskGroup(of: [UserAccount].self) { group in
                for chunk in chunks {
                    group.addTask { [db] in
                        let snap = try await db.collection("users")
                            .whereField("phoneNumber", in: chunk)
                            .getDocuments()
                        return snap.documents.compactMap { Self.account(from: $0) }
                    }
                }
                var result: [UserAccount] = []
                for try await part in group { result.append(contentsOf: part) }
                return result
            }
        } catch { throw FirebaseErrorMapper.map(error) }
    }
}
