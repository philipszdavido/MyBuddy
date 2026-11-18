//
//  Models.swift
//  MyBuddy
//
//  Backend-independent domain types. No Firebase imports allowed here.
//

import Foundation

struct AuthUser: Sendable, Equatable {
    let id: String
    let email: String?
    let isEmailVerified: Bool
}

struct UserAccount: Sendable, Equatable, Identifiable {
    let id: String
    var email: String
    var displayName: String
    var phoneNumber: Int64
    var photoURL: String?
    var createdAt: Date
}

enum DeliveryState: Int16, Sendable {
    case sending = 0   // local only / pending synchronization
    case sent = 1
    case failed = 2

    /// `sent` (server-acknowledged) always wins; otherwise the persisted state decides between sending and failed.
    static func resolve(sent: Bool, rawState: Int16) -> DeliveryState {
        if sent { return .sent }
        return DeliveryState(rawValue: rawState) == .failed ? .failed : .sending
    }
}

struct ChatMessage: Sendable, Equatable, Identifiable {
    let id: String
    let conversationID: String
    let senderID: String
    let recipientID: String
    var content: String
    var timestamp: Date
    var type: String
    var mediaURL: String
    var senderPhoneNumber: Int64
    var recipientPhoneNumber: Int64
    var seen: Bool
    var state: DeliveryState
}

struct Conversation: Sendable, Equatable, Identifiable {
    let id: String
    let participants: [String]
    var lastMessage: String
    var lastSenderID: String
    var lastType: String
    var updatedAt: Date
    var currentUserPhoneNumber: Int64
    var recipientUserPhoneNumber: Int64
    var lastSenderPhoneNumber: Int64

    /// The other participant, or nil for malformed documents (never crashes).
    func otherParticipant(than userID: String) -> String? {
        participants.first { $0 != userID }
    }
}

/// Opaque-to-callers position in a message list, backend-agnostic.
struct MessageCursor: Sendable, Equatable {
    let timestamp: Date
    let id: String
}

struct MessagePage: Sendable {
    let messages: [ChatMessage]          // newest first
    let nextCursor: MessageCursor?       // nil when no more history
}

extension OutgoingMessage {
    func with(media: UploadedMedia) -> OutgoingMessage {
        var copy = OutgoingMessage(id: id, conversationID: conversationID, senderID: senderID, recipientID: recipientID,
                                   content: content, type: type, mediaURL: media.url,
                                   senderPhoneNumber: senderPhoneNumber, recipientPhoneNumber: recipientPhoneNumber)
        copy.mediaID = media.id
        return copy
    }
}

/// What the client supplies when sending. `id` is generated client-side so
/// retries are idempotent (same id → same document).
struct OutgoingMessage: Sendable {
    let id: String
    let conversationID: String
    let senderID: String
    let recipientID: String
    let content: String
    let type: String
    let mediaURL: String
    let senderPhoneNumber: Int64
    let recipientPhoneNumber: Int64
    /// Server media id of an uploaded attachment (MyBuddy API); Firebase only uses `mediaURL`.
    var mediaID: String? = nil
}

// MARK: - Feed

enum Reaction: String, Sendable {
    case like, dislike
}

struct FeedPost: Sendable, Equatable, Identifiable {
    let id: String
    let authorPhone: Int64
    var content: String
    var timestamp: Date
}

struct NewPost: Sendable {
    let id: String            // client-generated => retries are idempotent
    let authorID: String
    let authorPhone: Int64
    let content: String
}

struct ReactionSummary: Sendable, Equatable {
    var likes: Int
    var dislikes: Int
    var mine: Reaction?
}

// MARK: - Safety (blocking / reporting)

enum ReportReason: String, Sendable, CaseIterable {
    case spam, harassment, inappropriate, impersonation, other
}

struct BlockedUser: Sendable, Equatable, Identifiable {
    let id: String            // blocked user's uid
    var phoneNumber: Int64
    var displayName: String
    var blockedAt: Date
}
