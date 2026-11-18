//
//  SocialFeedViewModel.swift
//  MyBuddy
//
//  Feed state for the MyBuddy API backend: following/discover tabs, cursor pagination, optimistic
//  reactions with rollback, publishing (text, photos, videos) and batched impression reporting.
//

import Foundation
import UIKit

@MainActor
final class SocialFeedViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case following = "Following", discover = "Discover"
        var id: String { rawValue }
    }

    @Published var tab: Tab = .following
    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPublishing = false
    /// 0...1 across all attachments while publishing; nil when nothing is uploading.
    @Published private(set) var uploadProgress: Double?
    @Published private(set) var reachedEnd = false
    @Published var errorMessage: String?

    static let maxPostLength = 2000

    private let repository: SocialRepository
    private var cursor: String?
    private var loadGeneration = 0
    private var pendingImpressions = Set<String>()
    private var reported = Set<String>()
    private var reactionsInFlight = Set<String>()
    /// Reused when the user retries the same text after a failure, so the server never creates two posts.
    private var pendingPost: (text: String, id: String)?

    init(repository: SocialRepository) { self.repository = repository }

    func reload() async {
        loadGeneration += 1
        cursor = nil
        reachedEnd = false
        await loadMore(replacing: true)
    }

    func loadMoreIfNeeded(current post: Post) async {
        guard !reachedEnd, !isLoading, post.id == posts.last?.id else { return }
        await loadMore(replacing: false)
    }

    private func loadMore(replacing: Bool) async {
        let generation = loadGeneration
        isLoading = true
        defer { isLoading = false }
        do {
            let page = tab == .following
                ? try await repository.followingFeed(cursor: cursor)
                : try await repository.discoverFeed(cursor: cursor)
            guard generation == loadGeneration else { return } // tab switched meanwhile
            let fresh = page.items.filter { p in !posts.contains { $0.id == p.id } || replacing }
            posts = replacing ? page.items : posts + fresh
            cursor = page.nextCursor
            reachedEnd = page.nextCursor == nil
        } catch {
            report(error)
        }
    }

    // MARK: Publish

    /// Uploads attachments (presigned, processed server-side), then creates the post. Returns true on success.
    func publish(text: String, images: [UIImage], videos: [URL], audience: PostAudience) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isPublishing, !trimmed.isEmpty || !images.isEmpty || !videos.isEmpty else { return false }
        guard trimmed.count <= Self.maxPostLength else {
            errorMessage = String(localized: "feed.error.tooLong", defaultValue: "Posts can be at most 2,000 characters.")
            return false
        }
        isPublishing = true
        defer { isPublishing = false; uploadProgress = nil }
        let id = (pendingPost?.text == trimmed ? pendingPost?.id : nil) ?? UUID().uuidString
        pendingPost = (trimmed, id)
        do {
            var mediaIDs: [String] = []
            let total = Double(images.count + videos.count)
            if total > 0 { uploadProgress = 0 }
            for (i, image) in images.enumerated() {
                guard let prepared = await ImageProcessor.prepare(image, maxDimension: ImageProcessor.chatMaxDimension) else { continue }
                mediaIDs.append(try await repository.uploadMedia(prepared.data, mimeType: "image/jpeg", purpose: .post, onProgress: reporter(done: Double(i), total: total)).id)
            }
            for (i, video) in videos.enumerated() {
                let data = try Data(contentsOf: video)
                let mime = video.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4"
                mediaIDs.append(try await repository.uploadMedia(data, mimeType: mime, purpose: .post, onProgress: reporter(done: Double(images.count + i), total: total)).id)
            }
            let post = try await repository.createPost(NewPostInput(clientID: id, text: trimmed, mediaIDs: mediaIDs, audience: audience))
            pendingPost = nil
            if tab == .following { posts.insert(post, at: 0) }
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Maps one attachment's 0...1 progress onto the whole post's progress.
    private func reporter(done: Double, total: Double) -> @Sendable (Double) -> Void {
        { [weak self] p in Task { @MainActor in self?.uploadProgress = (done + p) / total } }
    }

    func delete(_ post: Post) async {
        let before = posts
        posts.removeAll { $0.id == post.id }
        do { try await repository.deletePost(id: post.id) }
        catch { posts = before; report(error) }
    }

    // MARK: Engagement

    /// Optimistic: the UI updates immediately; the server's counts win once it answers, and a failure rolls back.
    func toggle(_ reaction: ReactionKind, on post: Post) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }), reactionsInFlight.insert(post.id).inserted else { return }
        let previous = posts[index]
        let next: ReactionKind? = previous.myReaction == reaction ? nil : reaction
        posts[index] = Self.applying(next, to: previous)
        Task {
            defer { reactionsInFlight.remove(post.id) }
            do {
                let counts = try await repository.react(postID: post.id, next)
                if let i = posts.firstIndex(where: { $0.id == post.id }) {
                    posts[i].counts.likes = counts.likes
                    posts[i].counts.dislikes = counts.dislikes
                    posts[i].myReaction = counts.mine
                }
            } catch {
                if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i] = previous }
                report(error)
            }
        }
    }

    func toggleSaved(_ post: Post) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let saved = !posts[index].saved
        posts[index].saved = saved
        Task {
            do { try await repository.setSaved(postID: post.id, saved) }
            catch {
                if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i].saved = !saved }
                report(error)
            }
        }
    }

    func repost(_ post: Post) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }), !posts[index].reposted else { return }
        posts[index].reposted = true
        posts[index].counts.reposts += 1
        Task {
            do { try await repository.repost(postID: post.id) }
            catch {
                if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i].reposted = false; posts[i].counts.reposts -= 1 }
                report(error)
            }
        }
    }

    static func applying(_ reaction: ReactionKind?, to post: Post) -> Post {
        var p = post
        if p.myReaction == .like { p.counts.likes -= 1 }
        if p.myReaction == .dislike { p.counts.dislikes -= 1 }
        if reaction == .like { p.counts.likes += 1 }
        if reaction == .dislike { p.counts.dislikes += 1 }
        p.myReaction = reaction
        return p
    }

    // MARK: Impressions

    /// Posts that appeared on screen are reported in batches (once per post per session).
    func appeared(_ post: Post) {
        guard reported.insert(post.id).inserted else { return }
        pendingImpressions.insert(post.id)
        if pendingImpressions.count >= 10 { flushImpressions() }
    }

    func flushImpressions() {
        let ids = Array(pendingImpressions)
        pendingImpressions.removeAll()
        guard !ids.isEmpty else { return }
        let repository = repository
        Task { await repository.reportImpressions(postIDs: ids) }
    }

    private func report(_ error: Error) {
        let e = AppError.wrap(error)
        if case .cancelled = e { return }
        Log.feed.error("social feed: \(e.diagnostic, privacy: .public)")
        errorMessage = e.userMessage
    }
}
