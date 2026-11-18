//
//  Messaging.swift
//  MyBuddy
//
//  Conversation model for the MyBuddy API: direct and group chats, message requests, receipts and
//  typing. (The Firebase backend keeps the Core Data chat in models/ and views/chats.)
//

import Foundation

enum ConversationKind: String, Sendable { case direct = "DIRECT", group = "GROUP" }

struct ChatParticipant: Sendable, Equatable, Identifiable {
    let user: UserSummary
    let isAdmin: Bool
    /// nil when the participant hides read receipts
    let lastReadSeq: Int?

    var id: String { user.id }
}

enum ChatMessageKind: String, Sendable { case text = "TEXT", image = "IMAGE", video = "VIDEO", system = "SYSTEM" }

struct ChatItem: Sendable, Equatable, Identifiable {
    let id: String
    let clientID: String
    let conversationID: String
    let seq: Int
    let sender: UserSummary?
    let senderID: String
    let kind: ChatMessageKind
    var text: String?
    var media: [MediaItem]
    var replyToText: String?
    var reactions: [String: Int]
    var edited: Bool
    var deleted: Bool
    let createdAt: Date
}

struct ChatConversation: Sendable, Equatable, Identifiable {
    let id: String
    let kind: ConversationKind
    var title: String?
    var participants: [ChatParticipant]
    var lastMessage: ChatItem?
    var lastSeq: Int
    var unreadCount: Int
    var isRequest: Bool
    var muted: Bool
    var lastActivity: Date

    /// Everyone except `me`.
    func others(_ me: String) -> [ChatParticipant] { participants.filter { $0.id != me } }

    /// Group title, or the other person's name for a direct chat.
    func displayName(me: String) -> String {
        if let title, !title.isEmpty { return title }
        let names = others(me).map(\.user.displayName)
        if names.isEmpty { return String(localized: "Just you") }
        return kind == .group ? names.prefix(3).joined(separator: ", ") : names[0]
    }

    func isAdmin(_ userID: String) -> Bool { participants.first { $0.id == userID }?.isAdmin ?? false }
}

/// Live events for open conversations.
enum ChatEvent: Sendable {
    /// (Re)connected: refetch, events may have been missed.
    case connected
    case message(ChatItem)
    case messageDeleted(conversationID: String, messageID: String)
    case conversationChanged(String)
    case read(conversationID: String, userID: String, seq: Int)
    case typing(conversationID: String, userID: String, isTyping: Bool)
}

protocol MessagingRepository: Sendable {
    /// The signed-in user's id on this backend.
    func currentUserID() async throws -> String
    func conversations(requests: Bool, cursor: String?) async throws -> Page<ChatConversation>
    func conversation(id: String) async throws -> ChatConversation
    /// Newest first when paging back with `beforeSeq`; oldest first with `afterSeq`.
    func messages(conversationID: String, beforeSeq: Int?, afterSeq: Int?) async throws -> (items: [ChatItem], hasMore: Bool)
    /// Idempotent on `clientID`.
    func send(conversationID: String, clientID: String, text: String?, mediaIDs: [String]) async throws -> ChatItem
    /// One participant → direct chat (reused if it exists), more → group.
    func startConversation(with userIDs: [String], title: String?) async throws -> ChatConversation
    func accept(conversationID: String) async throws
    /// Group: leave. Direct: delete history for me (also declines a request).
    func leave(conversationID: String) async throws
    func rename(conversationID: String, title: String) async throws -> ChatConversation
    func setMuted(conversationID: String, _ muted: Bool) async throws
    func addMembers(conversationID: String, userIDs: [String]) async throws -> ChatConversation
    func removeMember(conversationID: String, userID: String) async throws
    func markRead(conversationID: String, seq: Int) async
    func deleteMessage(id: String) async throws
    func typing(conversationID: String, isTyping: Bool)
    func events() -> AsyncStream<ChatEvent>
    /// People the user can start a chat with: matched contacts first.
    func contacts() async throws -> [UserSummary]
    func requestCount() async throws -> Int
}
