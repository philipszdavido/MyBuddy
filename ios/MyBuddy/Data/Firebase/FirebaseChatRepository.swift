//
//  FirebaseChatRepository.swift
//  MyBuddy
//
//  Schema preserved from existing documents:
//    chats/{chatId}                 participants, lastMessage, lastSenderId, lastTimestamp,
//                                   updatedAt, *PhoneNumber fields, chatId, type
//    chats/{chatId}/messages/{id}   senderId, recipientId, content, timestamp, type, mediaUrl,
//                                   *PhoneNumber, chatId, seen, sent
//

import Foundation
import FirebaseFirestore

final class FirebaseChatRepository: ChatRepository, @unchecked Sendable {
    private let db: Firestore
    init(db: Firestore = Firestore.firestore()) { self.db = db }

    // MARK: Mapping

    private static func date(_ data: [String: Any], _ key: String) -> Date? {
        (data[key] as? Timestamp)?.dateValue()
    }

    private static func int64(_ data: [String: Any], _ key: String) -> Int64 {
        (data[key] as? NSNumber)?.int64Value ?? 0
    }

    static func message(from doc: QueryDocumentSnapshot) -> ChatMessage {
        // `.estimate` yields a local time for pending server timestamps instead of nil.
        let data = doc.data(with: .estimate)
        return ChatMessage(
            id: doc.documentID,
            conversationID: data["chatId"] as? String ?? doc.reference.parent.parent?.documentID ?? "",
            senderID: data["senderId"] as? String ?? "",
            recipientID: data["recipientId"] as? String ?? "",
            content: data["content"] as? String ?? "",
            timestamp: date(data, "timestamp") ?? Date(),
            type: data["type"] as? String ?? "text",
            mediaURL: data["mediaUrl"] as? String ?? "",
            senderPhoneNumber: int64(data, "senderPhoneNumber"),
            recipientPhoneNumber: int64(data, "recipientPhoneNumber"),
            seen: data["seen"] as? Bool ?? true,
            state: doc.metadata.hasPendingWrites ? .sending : .sent
        )
    }

    static func conversation(from doc: QueryDocumentSnapshot) -> Conversation {
        let data = doc.data(with: .estimate)
        return Conversation(
            id: doc.documentID,
            participants: data["participants"] as? [String] ?? [],
            lastMessage: data["lastMessage"] as? String ?? "",
            lastSenderID: data["lastSenderId"] as? String ?? "",
            lastType: data["type"] as? String ?? "text",
            updatedAt: date(data, "updatedAt") ?? Date(),
            currentUserPhoneNumber: int64(data, "currentUserPhoneNumber"),
            recipientUserPhoneNumber: int64(data, "recipientUserPhoneNumber"),
            lastSenderPhoneNumber: int64(data, "lastSenderPhoneNumber")
        )
    }

    // MARK: Streams (each listener is removed when the consuming task ends)

    func observeConversations(userID: String, limit: Int) -> AsyncThrowingStream<[Conversation], Error> {
        let query = db.collection("chats")
            .whereField("participants", arrayContains: userID)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
        return AsyncThrowingStream { continuation in
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: FirebaseErrorMapper.map(error))
                    return
                }
                guard let snapshot else { return }
                continuation.yield(snapshot.documents.map(Self.conversation(from:)))
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    func observeLatestMessages(conversationID: String, limit: Int) -> AsyncThrowingStream<[ChatMessage], Error> {
        let query = db.collection("chats").document(conversationID).collection("messages")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
        return AsyncThrowingStream { continuation in
            let registration = query.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    continuation.finish(throwing: FirebaseErrorMapper.map(error))
                    return
                }
                guard let snapshot else { return }
                continuation.yield(snapshot.documents.map(Self.message(from:)))
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    // MARK: Pagination

    func loadOlderMessages(conversationID: String, before cursor: MessageCursor, limit: Int) async throws -> MessagePage {
        do {
            // Known limitation: messages sharing the exact same server timestamp as the cursor
            // are skipped. Acceptable for 1:1 chat; a composite (timestamp, id) cursor needs an index.
            let snap = try await db.collection("chats").document(conversationID).collection("messages")
                .order(by: "timestamp", descending: true)
                .start(after: [Timestamp(date: cursor.timestamp)])
                .limit(to: limit)
                .getDocuments()
            let messages = snap.documents.map(Self.message(from:))
            let next = messages.count == limit ? messages.last.map { MessageCursor(timestamp: $0.timestamp, id: $0.id) } : nil
            return MessagePage(messages: messages, nextCursor: next)
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    // MARK: Conversation id

    /// Legacy scheme: the two phone numbers, sorted and joined. No network needed; the chat document is
    /// created by the first message.
    func conversationID(currentUserID: String, currentPhone: Int64, recipientID: String, recipientPhone: Int64) async throws -> String {
        [String(currentPhone), String(recipientPhone)].sorted().joined(separator: "_")
    }

    // MARK: Send (single atomic batch, idempotent on message id)

    func send(_ message: OutgoingMessage) async throws {
        let chatRef = db.collection("chats").document(message.conversationID)
        let messageRef = chatRef.collection("messages").document(message.id)
        let now = FieldValue.serverTimestamp()
        let batch = db.batch()

        // merge:true creates the chat on first message and updates it afterwards,
        // removing the previous read-then-write race.
        batch.setData([
            "participants": [message.senderID, message.recipientID],
            "lastMessage": message.content,
            "lastSenderId": message.senderID,
            "lastTimestamp": now,
            "updatedAt": now,
            "recipientUserPhoneNumber": message.recipientPhoneNumber,
            "currentUserPhoneNumber": message.senderPhoneNumber,
            "lastSenderPhoneNumber": message.senderPhoneNumber,
            "chatId": message.conversationID,
            "type": message.type
        ], forDocument: chatRef, merge: true)

        // Same id on retry overwrites with identical content → no duplicates.
        batch.setData([
            "senderId": message.senderID,
            "recipientId": message.recipientID,
            "content": message.content,
            "timestamp": now,
            "type": message.type,
            "mediaUrl": message.mediaURL,
            "recipientPhoneNumber": message.recipientPhoneNumber,
            "senderPhoneNumber": message.senderPhoneNumber,
            "chatId": message.conversationID,
            "seen": false,
            "sent": true
        ], forDocument: messageRef)

        do { try await batch.commit() }
        catch { throw FirebaseErrorMapper.map(error) }
    }
}
