//
//  FirebaseSafetyRepository.swift
//
//    users/{uid}/blocks/{blockedUid}   phoneNumber, displayName, createdAt   (owner-only)
//    reports/{autoId}                  reporterId, targetUserId, reason, conversationId?, messageId?, createdAt, status
//  Security rules (not the client) stop a blocked user from messaging the blocker; see firestore.rules.proposed.
//

import Foundation
import FirebaseFirestore

final class FirebaseSafetyRepository: SafetyRepository, @unchecked Sendable {
    private let db: Firestore
    init(db: Firestore = Firestore.firestore()) { self.db = db }

    private func blocks(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("blocks")
    }

    func block(_ user: BlockedUser, by userID: String) async throws {
        do {
            try await blocks(userID).document(user.id).setData([
                "phoneNumber": user.phoneNumber,
                "displayName": user.displayName,
                "createdAt": FieldValue.serverTimestamp()
            ])
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    func unblock(userID: String, by blockerID: String) async throws {
        do { try await blocks(blockerID).document(userID).delete() }
        catch { throw FirebaseErrorMapper.map(error) }
    }

    func observeBlockedUsers(for userID: String, limit: Int) -> AsyncThrowingStream<[BlockedUser], Error> {
        let query = blocks(userID).order(by: "createdAt", descending: true).limit(to: limit)
        return AsyncThrowingStream { continuation in
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: FirebaseErrorMapper.map(error))
                    return
                }
                guard let snapshot else { return }
                continuation.yield(snapshot.documents.map { doc in
                    let data = doc.data(with: .estimate)
                    return BlockedUser(
                        id: doc.documentID,
                        phoneNumber: (data["phoneNumber"] as? NSNumber)?.int64Value ?? 0,
                        displayName: data["displayName"] as? String ?? "",
                        blockedAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    )
                })
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    func report(targetUserID: String, reporterID: String, reason: ReportReason,
                conversationID: String?, messageID: String?) async throws {
        var fields: [String: Any] = [
            "reporterId": reporterID,
            "targetUserId": targetUserID,
            "reason": reason.rawValue,
            "status": "open",
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let conversationID { fields["conversationId"] = conversationID }
        if let messageID { fields["messageId"] = messageID }
        do { _ = try await db.collection("reports").addDocument(data: fields) }
        catch { throw FirebaseErrorMapper.map(error) }
    }
}
