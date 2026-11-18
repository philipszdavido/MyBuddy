//
//  APIModels.swift
//  MyBuddy
//
//  Wire format of the MyBuddy API (see backend/openapi.json) and its mapping to Domain types.
//  Only the fields the app uses are declared; unknown fields are ignored, so the server can add
//  fields without breaking shipped clients.
//

import Foundation

struct PageDTO<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
    let nextCursor: String?
}

struct UserSummaryDTO: Decodable, Sendable {
    let id: String
    let username: String?
    let displayName: String
    let avatarUrl: String?
    let isVerified: Bool

    var domain: UserSummary {
        UserSummary(id: id, username: username, displayName: displayName, avatarURL: avatarUrl.flatMap(URL.init(string:)), isVerified: isVerified)
    }
}

struct RelationshipDTO: Decodable, Sendable {
    let following: Bool
    let followedBy: Bool
    let requested: Bool?
    let blocking: Bool?
    let muting: Bool?
    let isContact: Bool?

    var domain: Relationship {
        Relationship(following: following, followedBy: followedBy, requested: requested ?? false,
                     blocking: blocking ?? false, muting: muting ?? false, isContact: isContact ?? false)
    }
}

struct MeDTO: Decodable, Sendable {
    let id: String
    let username: String?
    let displayName: String
    let avatarUrl: String?
    let email: String?
    let phoneNumber: String?
    let joinedAt: Date

    var account: UserAccount {
        UserAccount(id: id, email: email ?? "", displayName: displayName, phoneNumber: Int64(phoneNumber ?? "") ?? 0,
                    photoURL: avatarUrl, createdAt: joinedAt)
    }
}

struct ProfileDTO: Decodable, Sendable {
    let id: String
    let username: String?
    let displayName: String
    let avatarUrl: String?
    let coverUrl: String?
    let isVerified: Bool
    let bio: String?
    let location: String?
    let website: String?
    let visibility: String
    let followersCount: Int
    let followingCount: Int
    let postsCount: Int
    let joinedAt: Date
    let relationship: RelationshipDTO?

    var domain: Profile {
        Profile(
            user: UserSummary(id: id, username: username, displayName: displayName, avatarURL: avatarUrl.flatMap(URL.init(string:)), isVerified: isVerified),
            bio: bio, location: location, website: website, coverURL: coverUrl.flatMap(URL.init(string:)),
            visibility: AccountVisibility(rawValue: visibility) ?? .public,
            followersCount: followersCount, followingCount: followingCount, postsCount: postsCount,
            joinedAt: joinedAt, relationship: relationship?.domain
        )
    }

    var account: UserAccount {
        UserAccount(id: id, email: "", displayName: displayName, phoneNumber: 0, photoURL: avatarUrl, createdAt: joinedAt)
    }
}

struct ContactDTO: Decodable, Sendable {
    let id: String
    let displayName: String
    let avatarUrl: String?
    let phoneNumber: String?
    let since: Date

    var account: UserAccount {
        UserAccount(id: id, email: "", displayName: displayName, phoneNumber: Int64(phoneNumber ?? "") ?? 0, photoURL: avatarUrl, createdAt: since)
    }
}

struct MediaDTO: Decodable, Sendable {
    let id: String
    let kind: String
    let status: String
    let width: Int?
    let height: Int?
    let durationMs: Int?
    let urls: [String: String]

    var domain: MediaItem {
        MediaItem(id: id, kind: MediaKind(rawValue: kind) ?? .image, status: MediaStatus(rawValue: status) ?? .processing,
                  width: width, height: height, durationMs: durationMs, urls: urls.compactMapValues(URL.init(string:)))
    }
}

struct CountsDTO: Decodable, Sendable {
    let likes: Int, dislikes: Int, comments: Int, reposts: Int, shares: Int, saves: Int
}

struct PostViewerDTO: Decodable, Sendable {
    let reaction: String?
    let saved: Bool
    let reposted: Bool
    let canEdit: Bool
}

/// Repost originals are one level deep on the server, so the nested type has no `repostOf`.
struct NestedPostDTO: Decodable, Sendable {
    let id: String
    let author: UserSummaryDTO
    let text: String?
    let media: [MediaDTO]
    let publishedAt: Date?
}

struct PostDTO: Decodable, Sendable {
    let id: String
    let kind: String
    let author: UserSummaryDTO
    let text: String?
    let audience: String
    let media: [MediaDTO]
    let hashtags: [String]
    let counts: CountsDTO
    let viewer: PostViewerDTO
    let repostOf: NestedPostDTO?
    let repostUnavailable: Bool
    let publishedAt: Date?
    let createdAt: Date

    var domain: Post {
        Post(
            id: id, kind: kind, author: author.domain, text: text,
            audience: PostAudience(rawValue: audience) ?? .contacts,
            media: media.map(\.domain), hashtags: hashtags,
            counts: PostCounts(likes: counts.likes, dislikes: counts.dislikes, comments: counts.comments,
                               reposts: counts.reposts, shares: counts.shares, saves: counts.saves),
            myReaction: viewer.reaction.flatMap(ReactionKind.init(rawValue:)),
            saved: viewer.saved, reposted: viewer.reposted, canEdit: viewer.canEdit,
            repostOf: repostOf.map { PostSnapshot(id: $0.id, author: $0.author.domain, text: $0.text, media: $0.media.map(\.domain), publishedAt: $0.publishedAt) },
            repostUnavailable: repostUnavailable, publishedAt: publishedAt, createdAt: createdAt
        )
    }
}

struct ReactionSummaryDTO: Decodable, Sendable {
    let likes: Int
    let dislikes: Int
    let mine: String?

    var domain: ReactionCounts { ReactionCounts(likes: likes, dislikes: dislikes, mine: mine.flatMap(ReactionKind.init(rawValue:))) }
}

struct CommentDTO: Decodable, Sendable {
    struct Counts: Decodable, Sendable { let likes: Int; let replies: Int }
    struct Viewer: Decodable, Sendable { let reaction: String?; let canEdit: Bool; let canDelete: Bool }
    let id: String
    let postId: String
    let parentId: String?
    let rootId: String?
    let author: UserSummaryDTO?
    let text: String?
    let deleted: Bool
    let counts: Counts
    let viewer: Viewer
    let createdAt: Date

    var domain: Comment {
        Comment(id: id, postID: postId, parentID: parentId, rootID: rootId, author: author?.domain, text: text, deleted: deleted,
                likes: counts.likes, replies: counts.replies, myReaction: viewer.reaction.flatMap(ReactionKind.init(rawValue:)),
                canEdit: viewer.canEdit, canDelete: viewer.canDelete, createdAt: createdAt)
    }
}

struct NotificationDTO: Decodable, Sendable {
    let id: String
    let type: String
    let actor: UserSummaryDTO?
    let postId: String?
    let deepLink: String
    let read: Bool
    let createdAt: Date

    var domain: ActivityItem? {
        guard let t = ActivityType(rawValue: type) else { return nil } // a type this build doesn't know
        return ActivityItem(id: id, type: t, actor: actor?.domain, postID: postId, deepLink: URL(string: deepLink), read: read, createdAt: createdAt)
    }
}

struct UploadTicketDTO: Decodable, Sendable {
    let mediaId: String
    let uploadUrl: String
    let method: String
    let headers: [String: String]
}

// MARK: Messaging

struct MessageDTO: Decodable, Sendable {
    struct Reply: Decodable, Sendable { let text: String?; let deleted: Bool }
    struct ReactionGroup: Decodable, Sendable { let emoji: String; let count: Int }
    let id: String
    let clientId: String
    let conversationId: String
    let seq: Int
    let senderId: String
    let sender: UserSummaryDTO?
    let type: String
    let text: String?
    let media: [MediaDTO]
    let replyTo: Reply?
    let reactions: [ReactionGroup]?
    let editedAt: Date?
    let deleted: Bool
    let createdAt: Date

    var domain: ChatItem {
        ChatItem(id: id, clientID: clientId, conversationID: conversationId, seq: seq, sender: sender?.domain, senderID: senderId,
                 kind: ChatMessageKind(rawValue: type) ?? .text, text: text, media: media.map(\.domain),
                 replyToText: replyTo.map { $0.deleted ? String(localized: "Deleted message") : ($0.text ?? "") },
                 reactions: Dictionary((reactions ?? []).map { ($0.emoji, $0.count) }, uniquingKeysWith: +),
                 edited: editedAt != nil, deleted: deleted, createdAt: createdAt)
    }
}

struct ParticipantDTO: Decodable, Sendable {
    let id: String
    let displayName: String
    let username: String?
    let avatarUrl: String?
    let isVerified: Bool?
    let role: String?
    let lastReadSeq: Int?
    let phoneNumber: String?

    var domain: ChatParticipant {
        ChatParticipant(user: UserSummary(id: id, username: username, displayName: displayName, avatarURL: avatarUrl.flatMap(URL.init(string:)), isVerified: isVerified ?? false),
                        isAdmin: role == "ADMIN", lastReadSeq: lastReadSeq)
    }
}

struct ConversationDTO: Decodable, Sendable {
    let id: String
    let kind: String
    let title: String?
    let participants: [ParticipantDTO]
    let lastMessage: MessageDTO?
    let lastSeq: Int
    let unreadCount: Int?
    let isRequest: Bool?
    let mutedUntil: Date?
    let lastMessageAt: Date?
    let createdAt: Date

    var domain: ChatConversation {
        ChatConversation(id: id, kind: ConversationKind(rawValue: kind) ?? .direct, title: title, participants: participants.map(\.domain),
                         lastMessage: lastMessage?.domain, lastSeq: lastSeq, unreadCount: unreadCount ?? 0, isRequest: isRequest ?? false,
                         muted: (mutedUntil ?? .distantPast) > Date(), lastActivity: lastMessageAt ?? createdAt)
    }
}

struct MessagesPageDTO: Decodable, Sendable {
    let items: [MessageDTO]
    let hasMore: Bool
}

struct BlockedDTO: Decodable, Sendable {
    let id: String
    let displayName: String
    let since: Date
}
