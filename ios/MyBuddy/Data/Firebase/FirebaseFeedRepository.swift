//
//  FirebaseFeedRepository.swift
//  MyBuddy
//
//  Existing schema is preserved:
//    user_feed/{ownerPhone}/posts/{postId}   content, feedOwnerId (author phone, String), timestamp, likes, dislikes
//  The legacy `likes`/`dislikes` fields are still written as 0 for old clients but are no longer updated.
//  New (additive):
//    post_reactions/{postId}/users/{uid}     type: "like" | "dislike", createdAt
//  Counts come from server-side aggregation queries, so there are no hot counter documents.
//

import Foundation
import FirebaseFirestore

final class FirebaseFeedRepository: FeedRepository, @unchecked Sendable {
    private let db: Firestore
    /// Firestore allows 500 writes per batch; stay below it.
    private static let batchSize = 400

    init(db: Firestore = Firestore.firestore()) { self.db = db }

    func observeFeed(ownerPhone: Int64, limit: Int) -> AsyncThrowingStream<[FeedPost], Error> {
        let query = db.collection("user_feed").document(String(ownerPhone)).collection("posts")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
        return AsyncThrowingStream { continuation in
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: FirebaseErrorMapper.map(error))
                    return
                }
                guard let snapshot else { return }
                let posts: [FeedPost] = snapshot.documents.compactMap { doc in
                    let data = doc.data(with: .estimate)
                    guard let authorString = data["feedOwnerId"] as? String, let author = Int64(authorString) else { return nil }
                    return FeedPost(
                        id: doc.documentID,
                        authorPhone: author,
                        content: data["content"] as? String ?? "",
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                    )
                }
                continuation.yield(posts)
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    func publish(_ post: NewPost, recipientPhones: [Int64]) async throws {
        // Author first so their own post appears even if a later chunk fails.
        var targets = [post.authorPhone]
        targets += Set(recipientPhones.filter { $0 > 0 && $0 != post.authorPhone })

        do {
            for start in stride(from: 0, to: targets.count, by: Self.batchSize) {
                let chunk = targets[start..<min(start + Self.batchSize, targets.count)]
                let batch = db.batch()
                for phone in chunk {
                    // Deterministic document id => retrying republishes instead of duplicating.
                    let ref = db.collection("user_feed").document(String(phone)).collection("posts").document(post.id)
                    batch.setData([
                        "content": post.content,
                        "feedOwnerId": String(post.authorPhone),
                        "timestamp": FieldValue.serverTimestamp(),
                        "likes": 0,
                        "dislikes": 0
                    ], forDocument: ref)
                }
                try await batch.commit()
            }
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    private func reactionRef(_ postID: String, _ userID: String) -> DocumentReference {
        db.collection("post_reactions").document(postID).collection("users").document(userID)
    }

    func setReaction(postID: String, userID: String, reaction: Reaction?) async throws {
        do {
            if let reaction {
                try await reactionRef(postID, userID).setData([
                    "type": reaction.rawValue,
                    "createdAt": FieldValue.serverTimestamp()
                ])
            } else {
                try await reactionRef(postID, userID).delete()
            }
        } catch { throw FirebaseErrorMapper.map(error) }
    }

    func reactionSummary(postID: String, userID: String) async throws -> ReactionSummary {
        let users = db.collection("post_reactions").document(postID).collection("users")
        do {
            async let likes = users.whereField("type", isEqualTo: Reaction.like.rawValue)
                .count.getAggregation(source: .server)
            async let dislikes = users.whereField("type", isEqualTo: Reaction.dislike.rawValue)
                .count.getAggregation(source: .server)
            async let mine = reactionRef(postID, userID).getDocument()
            let (l, d, m) = try await (likes, dislikes, mine)
            return ReactionSummary(
                likes: l.count.intValue,
                dislikes: d.count.intValue,
                mine: (m.data()?["type"] as? String).flatMap(Reaction.init(rawValue:))
            )
        } catch { throw FirebaseErrorMapper.map(error) }
    }
}
