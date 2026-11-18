//
//  FeedViewModel.swift
//  MyBuddy
//
//  UI-facing feed state. Talks only to `FeedRepository`; the Core Data `Feed`
//  rows remain the cache the list renders from.
//

import Foundation
import CoreData

@MainActor
final class FeedViewModel: ObservableObject {
    static let feedWindow = 50
    static let maxPostLength = 2000

    @Published private(set) var myReactions: [String: Reaction] = [:]
    @Published private(set) var isPublishing = false
    @Published var errorMessage: String?

    private let repository: FeedRepository
    private let coreData = CoreDataUtils.shared
    private var summarized = Set<String>()
    private var reactionsInFlight = Set<String>()
    private var pendingPost: (content: String, id: String)?

    init(repository: FeedRepository = AppContainer.shared.feedRepository) {
        self.repository = repository
    }

    // MARK: Sync

    /// Run from `.task`; ends (and removes the backend listener) when the view goes away.
    func syncFeed() async {
        guard let user = coreData.fetchUserData(), let uid = user.id else { return }
        do {
            for try await posts in repository.observeFeed(ownerPhone: user.phoneNumber, limit: Self.feedWindow) {
                for post in posts {
                    coreData.insertFeed(id: post.id, timestamp: post.timestamp, feedOwnerId: post.authorPhone,
                                        content: post.content, likes: nil, dislikes: nil)
                }
                await loadSummaries(for: posts.map(\.id), userID: uid, force: false)
            }
        } catch {
            report(error)
        }
    }

    /// Pull-to-refresh: re-reads reaction counts for the visible window.
    func refresh() async {
        guard let uid = coreData.fetchUserData()?.id else { return }
        let request: NSFetchRequest<Feed> = Feed.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = Self.feedWindow
        let ids = ((try? coreData.managedObjectContext.fetch(request)) ?? []).compactMap(\.id)
        await loadSummaries(for: ids, userID: uid, force: true)
    }

    private func loadSummaries(for ids: [String], userID: String, force: Bool) async {
        for id in ids {
            if Task.isCancelled { return }
            if !force && !summarized.insert(id).inserted { continue }
            do {
                let summary = try await repository.reactionSummary(postID: id, userID: userID)
                summarized.insert(id)
                myReactions[id] = summary.mine
                coreData.insertFeed(id: id, timestamp: nil, feedOwnerId: nil, content: nil,
                                    likes: Int64(summary.likes), dislikes: Int64(summary.dislikes))
            } catch {
                summarized.remove(id)
                Log.feed.error("reaction summary failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
            }
        }
    }

    // MARK: Publish

    /// Returns true when the post was accepted by the backend.
    func publish(content: String) async -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isPublishing else { return false }
        guard text.count <= Self.maxPostLength else {
            errorMessage = String(localized: "feed.error.tooLong", defaultValue: "Posts can be at most 2,000 characters.")
            return false
        }
        guard let user = coreData.fetchUserData(), let uid = user.id else {
            errorMessage = AppError.authentication(.notSignedIn).userMessage
            return false
        }
        let recipients = coreData.loadContacts().map(\.phoneNumber).filter { $0 > 0 && $0 != user.phoneNumber }

        // Reuse the id when the user retries the same text after a failure.
        let id = (pendingPost?.content == text ? pendingPost?.id : nil) ?? UUID().uuidString
        pendingPost = (text, id)
        isPublishing = true
        defer { isPublishing = false }

        do {
            try await repository.publish(NewPost(id: id, authorID: uid, authorPhone: user.phoneNumber, content: text),
                                         recipientPhones: recipients)
            pendingPost = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    // MARK: Reactions

    func react(to feed: Feed, _ reaction: Reaction) {
        guard let id = feed.id, let uid = coreData.fetchUserData()?.id,
              reactionsInFlight.insert(id).inserted else { return }   // ignore taps while a write is in flight
        let previous = myReactions[id]
        let new: Reaction? = (previous == reaction) ? nil : reaction

        apply(feed, from: previous, to: new)           // optimistic
        myReactions[id] = new

        let repository = repository
        Task {
            defer { reactionsInFlight.remove(id) }
            do {
                try await repository.setReaction(postID: id, userID: uid, reaction: new)
            } catch {
                apply(feed, from: new, to: previous)   // roll back
                myReactions[id] = previous
                report(error)
            }
        }
    }

    private func apply(_ feed: Feed, from old: Reaction?, to new: Reaction?) {
        switch old {
        case .like: feed.likes = max(0, feed.likes - 1)
        case .dislike: feed.dislikes = max(0, feed.dislikes - 1)
        case nil: break
        }
        switch new {
        case .like: feed.likes += 1
        case .dislike: feed.dislikes += 1
        case nil: break
        }
        try? coreData.managedObjectContext.save()
    }

    private func report(_ error: Error) {
        let appError = AppError.wrap(error)
        if case .cancelled = appError { return }
        Log.feed.error("feed error: \(appError.diagnostic, privacy: .public)")
        errorMessage = appError.userMessage
    }
}
