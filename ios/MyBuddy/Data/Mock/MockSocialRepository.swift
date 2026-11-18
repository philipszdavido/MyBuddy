//
//  MockSocialRepository.swift
//  MyBuddy
//
//  In-memory SocialRepository for unit tests, previews and UI tests (MBUITesting=1).
//

import Foundation

final class MockSocialRepository: SocialRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var posts: [Post] = []
    private var commentsByPost: [String: [Comment]] = [:]
    private var activityItems: [ActivityItem] = []
    private var following = Set<String>()
    private(set) var impressions: [String] = []
    static let me = UserSummary(id: "me", username: "me", displayName: "Me", avatarURL: nil, isVerified: false)
    static let ada = UserSummary(id: "ada", username: "ada", displayName: "Ada", avatarURL: nil, isVerified: true)

    init(seed: Bool = true) {
        guard seed else { return }
        let now = Date()
        posts = [
            Post(id: "p1", kind: "text", author: Self.ada, text: "Welcome to MyBuddy! #hello", audience: .public, media: [], hashtags: ["hello"],
                 counts: PostCounts(likes: 3, dislikes: 0, comments: 1, reposts: 0, shares: 0, saves: 0), myReaction: nil, saved: false,
                 reposted: false, canEdit: false, repostOf: nil, repostUnavailable: false, publishedAt: now.addingTimeInterval(-3600), createdAt: now.addingTimeInterval(-3600)),
        ]
        commentsByPost["p1"] = [
            Comment(id: "c1", postID: "p1", parentID: nil, rootID: nil, author: Self.ada, text: "First!", deleted: false, likes: 0,
                    replies: 0, myReaction: nil, canEdit: false, canDelete: false, createdAt: now.addingTimeInterval(-1800)),
        ]
        activityItems = [
            ActivityItem(id: "n1", type: .follow, actor: Self.ada, postID: nil, deepLink: URL(string: "mybuddy://profile/ada"), read: false, createdAt: now),
        ]
    }

    func followingFeed(cursor: String?) async throws -> Page<Post> { lock.withLock { Page(items: posts, nextCursor: nil) } }
    func discoverFeed(cursor: String?) async throws -> Page<Post> { lock.withLock { Page(items: posts.filter { $0.audience == .public }, nextCursor: nil) } }

    func post(id: String) async throws -> Post {
        guard let p = lock.withLock({ posts.first { $0.id == id } }) else { throw AppError.notFound }
        return p
    }

    func createPost(_ input: NewPostInput) async throws -> Post {
        try lock.withLock {
            if let existing = posts.first(where: { $0.id == input.clientID }) { return existing }
            guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !input.mediaIDs.isEmpty else {
                throw AppError.validation("A post needs text or media")
            }
            let p = Post(id: input.clientID, kind: input.mediaIDs.isEmpty ? "text" : "image", author: Self.me, text: input.text, audience: input.audience,
                         media: input.mediaIDs.map { MediaItem(id: $0, kind: .image, status: .ready, width: 100, height: 100, durationMs: nil, urls: [:]) },
                         hashtags: [], counts: PostCounts(likes: 0, dislikes: 0, comments: 0, reposts: 0, shares: 0, saves: 0), myReaction: nil,
                         saved: false, reposted: false, canEdit: true, repostOf: nil, repostUnavailable: false, publishedAt: Date(), createdAt: Date())
            posts.insert(p, at: 0)
            return p
        }
    }

    func deletePost(id: String) async throws { lock.withLock { posts.removeAll { $0.id == id } } }

    func react(postID: String, _ reaction: ReactionKind?) async throws -> ReactionCounts {
        try lock.withLock {
            guard let i = posts.firstIndex(where: { $0.id == postID }) else { throw AppError.notFound }
            var p = posts[i]
            if p.myReaction == .like { p.counts.likes -= 1 }
            if p.myReaction == .dislike { p.counts.dislikes -= 1 }
            if reaction == .like { p.counts.likes += 1 }
            if reaction == .dislike { p.counts.dislikes += 1 }
            p.myReaction = reaction
            posts[i] = p
            return ReactionCounts(likes: p.counts.likes, dislikes: p.counts.dislikes, mine: reaction)
        }
    }

    func setSaved(postID: String, _ saved: Bool) async throws {
        lock.withLock { if let i = posts.firstIndex(where: { $0.id == postID }) { posts[i].saved = saved } }
    }

    func repost(postID: String) async throws {
        lock.withLock { if let i = posts.firstIndex(where: { $0.id == postID }) { posts[i].reposted = true; posts[i].counts.reposts += 1 } }
    }

    func reportImpressions(postIDs: [String]) async { lock.withLock { impressions += postIDs } }

    func comments(postID: String, cursor: String?) async throws -> Page<Comment> {
        lock.withLock { Page(items: (commentsByPost[postID] ?? []).filter { $0.rootID == nil }, nextCursor: nil) }
    }

    func replies(commentID: String, cursor: String?) async throws -> Page<Comment> {
        lock.withLock { Page(items: commentsByPost.values.flatMap { $0 }.filter { $0.rootID == commentID }, nextCursor: nil) }
    }

    func addComment(postID: String, text: String, parentID: String?, clientID: String) async throws -> Comment {
        lock.withLock {
            let all = commentsByPost[postID] ?? []
            if let existing = all.first(where: { $0.id == clientID }) { return existing }
            let root = parentID.flatMap { id in all.first { $0.id == id }.map { $0.rootID ?? $0.id } }
            let c = Comment(id: clientID, postID: postID, parentID: parentID, rootID: root, author: Self.me, text: text, deleted: false,
                            likes: 0, replies: 0, myReaction: nil, canEdit: true, canDelete: true, createdAt: Date())
            commentsByPost[postID, default: []].append(c)
            if let root, let i = commentsByPost[postID]?.firstIndex(where: { $0.id == root }) { commentsByPost[postID]?[i].replies += 1 }
            if let i = posts.firstIndex(where: { $0.id == postID }) { posts[i].counts.comments += 1 }
            return c
        }
    }

    func deleteComment(id: String) async throws {
        lock.withLock {
            for (post, list) in commentsByPost {
                if let i = list.firstIndex(where: { $0.id == id }) {
                    commentsByPost[post]?[i].deleted = true
                    commentsByPost[post]?[i].text = nil
                }
            }
        }
    }

    func reactToComment(id: String, _ reaction: ReactionKind?) async throws -> ReactionCounts {
        ReactionCounts(likes: reaction == .like ? 1 : 0, dislikes: reaction == .dislike ? 1 : 0, mine: reaction)
    }

    func profile(userID: String) async throws -> Profile {
        let user = userID == Self.ada.id ? Self.ada : Self.me
        let isFollowing = lock.withLock { following.contains(userID) }
        return Profile(user: user, bio: "Hello!", location: nil, website: nil, coverURL: nil, visibility: .public,
                       followersCount: isFollowing ? 1 : 0, followingCount: 0, postsCount: lock.withLock { posts.filter { $0.author.id == userID }.count },
                       joinedAt: Date(timeIntervalSince1970: 1_700_000_000),
                       relationship: userID == Self.me.id ? nil : Relationship(following: isFollowing, followedBy: false, requested: false, blocking: false, muting: false, isContact: false))
    }

    func posts(by userID: String, cursor: String?) async throws -> Page<Post> {
        lock.withLock { Page(items: posts.filter { $0.author.id == userID }, nextCursor: nil) }
    }

    func follow(userID: String) async throws -> FollowState { lock.withLock { _ = following.insert(userID) }; return .following }
    func unfollow(userID: String) async throws { lock.withLock { _ = following.remove(userID) } }

    func searchUsers(_ query: String, cursor: String?) async throws -> Page<UserSummary> {
        let q = query.lowercased()
        return Page(items: [Self.ada, Self.me].filter { ($0.username ?? "").contains(q) || $0.displayName.lowercased().contains(q) }, nextCursor: nil)
    }

    func searchPosts(_ query: String, cursor: String?) async throws -> Page<Post> {
        let q = query.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return lock.withLock { Page(items: posts.filter { ($0.text ?? "").lowercased().contains(q) }, nextCursor: nil) }
    }

    func trendingHashtags() async throws -> [String] { ["hello", "mybuddy"] }

    func activity(cursor: String?) async throws -> Page<ActivityItem> { lock.withLock { Page(items: activityItems, nextCursor: nil) } }
    func unreadActivityCount() async throws -> Int { lock.withLock { activityItems.filter { !$0.read }.count } }

    func markActivityRead(id: String?) async throws {
        lock.withLock {
            for i in activityItems.indices where id == nil || activityItems[i].id == id { activityItems[i].read = true }
        }
    }

    func uploadMedia(_ data: Data, mimeType: String, purpose: MediaPurpose, onProgress: (@Sendable (Double) -> Void)?) async throws -> MediaItem {
        onProgress?(1)
        return MediaItem(id: UUID().uuidString, kind: mimeType.hasPrefix("video/") ? .video : .image, status: .ready, width: 100, height: 100, durationMs: nil, urls: [:])
    }
}
