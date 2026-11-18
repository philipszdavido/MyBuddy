//
//  Social.swift
//  MyBuddy
//
//  Domain types for the social features served by the MyBuddy API (posts with media, comments,
//  profiles, follows, search, activity inbox). Backend-independent: no Firebase or networking here.
//

import Foundation

struct Page<T: Sendable>: Sendable {
    let items: [T]
    let nextCursor: String?
}

struct UserSummary: Sendable, Equatable, Hashable, Identifiable {
    let id: String
    let username: String?
    let displayName: String
    let avatarURL: URL?
    let isVerified: Bool
}

struct Relationship: Sendable, Equatable {
    var following: Bool
    var followedBy: Bool
    var requested: Bool
    var blocking: Bool
    var muting: Bool
    var isContact: Bool
}

enum AccountVisibility: String, Sendable, CaseIterable { case `public` = "PUBLIC", `private` = "PRIVATE" }

struct Profile: Sendable, Equatable, Identifiable {
    let user: UserSummary
    var bio: String?
    var location: String?
    var website: String?
    var coverURL: URL?
    var visibility: AccountVisibility
    var followersCount: Int
    var followingCount: Int
    var postsCount: Int
    var joinedAt: Date
    /// nil when viewing your own profile
    var relationship: Relationship?

    var id: String { user.id }
}

enum MediaKind: String, Sendable { case image = "IMAGE", video = "VIDEO" }
enum MediaStatus: String, Sendable { case pendingUpload = "PENDING_UPLOAD", processing = "PROCESSING", ready = "READY", failed = "FAILED" }

struct MediaItem: Sendable, Equatable, Identifiable {
    let id: String
    let kind: MediaKind
    let status: MediaStatus
    let width: Int?
    let height: Int?
    let durationMs: Int?
    /// Variant name (thumb, medium, large, poster, mp4_720, mp4_480) -> URL
    let urls: [String: URL]

    var displayURL: URL? { urls["medium"] ?? urls["large"] ?? urls["poster"] ?? urls["thumb"] }
    var videoURL: URL? { urls["mp4_720"] ?? urls["mp4_480"] }
    var aspectRatio: CGFloat? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }
}

enum PostAudience: String, Sendable, CaseIterable {
    case contacts = "CONTACTS", followers = "FOLLOWERS", `public` = "PUBLIC"
}

enum ReactionKind: String, Sendable { case like = "LIKE", dislike = "DISLIKE" }

struct PostCounts: Sendable, Equatable {
    var likes: Int
    var dislikes: Int
    var comments: Int
    var reposts: Int
    var shares: Int
    var saves: Int
}

struct Post: Sendable, Equatable, Identifiable {
    let id: String
    let kind: String
    let author: UserSummary
    var text: String?
    var audience: PostAudience
    var media: [MediaItem]
    var hashtags: [String]
    var counts: PostCounts
    var myReaction: ReactionKind?
    var saved: Bool
    var reposted: Bool
    var canEdit: Bool
    /// The original post of a repost or quote; nil when unavailable to the viewer.
    var repostOf: PostSnapshot?
    var repostUnavailable: Bool
    var publishedAt: Date?
    var createdAt: Date
}

/// A non-recursive copy of a post (for reposts/quotes), so `Post` stays a value type.
struct PostSnapshot: Sendable, Equatable {
    let id: String
    let author: UserSummary
    let text: String?
    let media: [MediaItem]
    let publishedAt: Date?
}

struct ReactionCounts: Sendable, Equatable {
    var likes: Int
    var dislikes: Int
    var mine: ReactionKind?
}

struct Comment: Sendable, Equatable, Identifiable {
    let id: String
    let postID: String
    let parentID: String?
    let rootID: String?
    let author: UserSummary?
    var text: String?
    var deleted: Bool
    var likes: Int
    var replies: Int
    var myReaction: ReactionKind?
    var canEdit: Bool
    var canDelete: Bool
    var createdAt: Date
}

enum ActivityType: String, Sendable {
    case follow = "FOLLOW", followRequest = "FOLLOW_REQUEST", followAccepted = "FOLLOW_ACCEPTED"
    case postReaction = "POST_REACTION", comment = "COMMENT", commentReply = "COMMENT_REPLY"
    case commentReaction = "COMMENT_REACTION", mention = "MENTION", repost = "REPOST"
    case message = "MESSAGE", messageRequest = "MESSAGE_REQUEST"
}

struct ActivityItem: Sendable, Equatable, Identifiable {
    let id: String
    let type: ActivityType
    let actor: UserSummary?
    let postID: String?
    let deepLink: URL?
    var read: Bool
    let createdAt: Date
}

struct NewPostInput: Sendable {
    let clientID: String
    let text: String
    let mediaIDs: [String]
    let audience: PostAudience
}

enum FollowState: String, Sendable { case following, requested, none }

/// Uploaded, server-verified media. `id` is what posts and messages reference.
struct UploadedMedia: Sendable, Equatable {
    let id: String
    let url: String
}

enum MediaPurpose: String, Sendable { case avatar = "AVATAR", cover = "COVER", post = "POST", message = "MESSAGE" }

/// Social features of the MyBuddy API. Every call acts as the signed-in user (identity comes from the
/// auth token, never from parameters).
protocol SocialRepository: Sendable {
    func followingFeed(cursor: String?) async throws -> Page<Post>
    func discoverFeed(cursor: String?) async throws -> Page<Post>
    func post(id: String) async throws -> Post
    func createPost(_ input: NewPostInput) async throws -> Post
    func deletePost(id: String) async throws
    func react(postID: String, _ reaction: ReactionKind?) async throws -> ReactionCounts
    func setSaved(postID: String, _ saved: Bool) async throws
    func repost(postID: String) async throws
    func reportImpressions(postIDs: [String]) async

    func comments(postID: String, cursor: String?) async throws -> Page<Comment>
    func replies(commentID: String, cursor: String?) async throws -> Page<Comment>
    func addComment(postID: String, text: String, parentID: String?, clientID: String) async throws -> Comment
    func deleteComment(id: String) async throws
    func reactToComment(id: String, _ reaction: ReactionKind?) async throws -> ReactionCounts

    func profile(userID: String) async throws -> Profile
    func posts(by userID: String, cursor: String?) async throws -> Page<Post>
    func follow(userID: String) async throws -> FollowState
    func unfollow(userID: String) async throws

    func searchUsers(_ query: String, cursor: String?) async throws -> Page<UserSummary>
    func searchPosts(_ query: String, cursor: String?) async throws -> Page<Post>
    func trendingHashtags() async throws -> [String]

    func activity(cursor: String?) async throws -> Page<ActivityItem>
    func unreadActivityCount() async throws -> Int
    func markActivityRead(id: String?) async throws

    /// Uploads directly to storage through a presigned URL and waits until the server has processed it.
    /// `onProgress` reports 0...1 (bytes sent up to 0.95, then processing).
    func uploadMedia(_ data: Data, mimeType: String, purpose: MediaPurpose, onProgress: (@Sendable (Double) -> Void)?) async throws -> MediaItem
}

extension SocialRepository {
    func uploadMedia(_ data: Data, mimeType: String, purpose: MediaPurpose) async throws -> MediaItem {
        try await uploadMedia(data, mimeType: mimeType, purpose: purpose, onProgress: nil)
    }
}
