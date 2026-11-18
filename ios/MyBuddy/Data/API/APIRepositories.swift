//
//  APIRepositories.swift
//  MyBuddy
//
//  MyBuddy API implementations of the Domain protocols. Selected by AppContainer when the app is
//  configured with an API base URL. Identity always comes from the bearer token; `userID` parameters
//  that the protocols carry for the Firebase backend are ignored here.
//

import Foundation

// MARK: - Users & contacts

final class APIUserRepository: UserRepository, @unchecked Sendable {
    private let api: APIClient
    private let authUID: @Sendable () -> String?

    /// `authUID` is the Firebase uid of the signed-in user; `account(id:)` with that id means "me".
    init(api: APIClient, authUID: @escaping @Sendable () -> String?) {
        self.api = api
        self.authUID = authUID
    }

    func account(id: String) async throws -> UserAccount? {
        if id == authUID() {
            let me: MeDTO = try await api.get("users/me")
            return me.account
        }
        do {
            let profile: ProfileDTO = try await api.get("users/id/\(id)")
            return profile.account
        } catch AppError.notFound {
            return nil
        }
    }

    func save(_ account: UserAccount) async throws {
        struct Body: Encodable { let displayName: String; let phoneNumber: String? }
        let phone = account.phoneNumber > 0 ? String(account.phoneNumber) : nil
        let _: EmptyResponse = try await api.patch("users/me", body: Body(displayName: account.displayName, phoneNumber: phone))
    }

    func updatePhoto(id: String, media: UploadedMedia?) async throws {
        struct Body: Encodable {
            let avatarMediaId: String?
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(avatarMediaId, forKey: .avatarMediaId) // explicit null removes the photo
            }
            enum CodingKeys: String, CodingKey { case avatarMediaId }
        }
        let _: EmptyResponse = try await api.patch("users/me", body: Body(avatarMediaId: media?.id))
    }

    func accounts(matchingPhoneNumbers numbers: [Int64]) async throws -> [UserAccount] {
        try await sync(numbers, mode: "merge")
    }

    func syncContacts(phoneNumbers numbers: [Int64]) async throws -> [UserAccount] {
        try await sync(numbers, mode: "replace")
    }

    private func sync(_ numbers: [Int64], mode: String) async throws -> [UserAccount] {
        struct Body: Encodable { let phoneNumbers: [String]; let mode: String }
        struct Result: Decodable { let matched: [ContactDTO] }
        let unique = Array(Set(numbers.filter { $0 > 0 })).prefix(5000).map(String.init)
        let result: Result = try await api.post("contacts/sync", body: Body(phoneNumbers: unique, mode: mode))
        return result.matched.map(\.account)
    }
}

// MARK: - Chat

/// Conversations and messages over REST, kept live by the realtime connection. Message ids exposed to the
/// app are the *client* ids, so the optimistic local row and the server echo are the same Core Data row.
final class APIChatRepository: ChatRepository, @unchecked Sendable {
    private let api: APIClient
    private let realtime: RealtimeClient
    private let decoder = APIClient.makeDecoder()
    private let lock = NSLock()
    /// Oldest seq seen per conversation, for history paging (the protocol's cursor is time-based).
    private var oldestSeq: [String: Int] = [:]
    private var conversations: [String: ConversationDTO] = [:]

    init(api: APIClient, realtime: RealtimeClient) {
        self.api = api
        self.realtime = realtime
    }

    func observeConversations(userID: String, limit: Int) -> AsyncThrowingStream<[Conversation], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Strong capture is fine: the task is cancelled when the consumer stops listening.
                let refresh = { () async in
                    do {
                        let page: PageDTO<ConversationDTO> = try await self.api.get("conversations", query: ["limit": String(min(limit, 100))])
                        self.lock.withLock { page.items.forEach { self.conversations[$0.id] = $0 } }
                        continuation.yield(page.items.map { self.conversation($0, me: userID) })
                    } catch {
                        Log.chat.error("conversation refresh failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
                    }
                }
                await refresh()
                for await signal in realtime.signals() {
                    switch signal {
                    case .connected: await refresh()
                    case .event(let name, _) where name == "message:new" || name == "conversation:updated" || name == "message:deleted":
                        await refresh()
                    default: break
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func observeLatestMessages(conversationID: String, limit: Int) -> AsyncThrowingStream<[ChatMessage], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var byClientID: [String: MessageDTO] = [:]
                var lastSeq = 0
                let emit = {
                    let sorted = byClientID.values.sorted { $0.seq > $1.seq } // newest first, like the Firebase stream
                    continuation.yield(sorted.map { self.message($0) })
                }
                let catchUp = { (initial: Bool) async in
                    do {
                        try await self.loadConversationIfNeeded(conversationID)
                        let page: MessagesPageDTO = initial || lastSeq == 0
                            ? try await self.api.get("conversations/\(conversationID)/messages", query: ["limit": String(min(limit, 100))])
                            : try await self.api.get("conversations/\(conversationID)/messages", query: ["afterSeq": String(lastSeq), "limit": "100"])
                        for m in page.items { byClientID[m.clientId] = m; lastSeq = max(lastSeq, m.seq) }
                        self.noteOldest(conversationID, page.items.map(\.seq).min())
                        emit()
                    } catch {
                        Log.chat.error("message sync failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
                    }
                }
                await catchUp(true)
                for await signal in realtime.signals() {
                    switch signal {
                    case .connected:
                        await catchUp(false)   // reconnect: fetch everything after the last seq we have
                    case .event(name: "message:new", let payload), .event(name: "message:updated", let payload):
                        guard let m = try? decoder.decode(MessageDTO.self, from: payload), m.conversationId == conversationID else { continue }
                        if m.seq > lastSeq + 1 { await catchUp(false) } // gap: something was missed
                        byClientID[m.clientId] = m
                        lastSeq = max(lastSeq, m.seq)
                        emit()
                    case .event(name: "message:deleted", _), .event(name: "conversation:read", _):
                        await catchUp(true)
                    default: break
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func loadOlderMessages(conversationID: String, before cursor: MessageCursor, limit: Int) async throws -> MessagePage {
        guard let before = lock.withLock({ oldestSeq[conversationID] }), before > 1 else {
            return MessagePage(messages: [], nextCursor: nil)
        }
        try await loadConversationIfNeeded(conversationID)
        let page: MessagesPageDTO = try await api.get("conversations/\(conversationID)/messages",
                                                     query: ["beforeSeq": String(before), "limit": String(min(limit, 100))])
        noteOldest(conversationID, page.items.map(\.seq).min())
        let messages = page.items.map(message)
        let next = page.hasMore ? messages.last.map { MessageCursor(timestamp: $0.timestamp, id: $0.id) } : nil
        return MessagePage(messages: messages, nextCursor: next)
    }

    func send(_ m: OutgoingMessage) async throws {
        struct Body: Encodable { let clientId: String; let text: String?; let mediaIds: [String]? }
        let body = Body(clientId: m.id, text: m.content.isEmpty ? nil : m.content, mediaIds: m.mediaID.map { [$0] })
        if m.mediaID == nil && m.content.isEmpty { throw AppError.validation("Nothing to send") }
        let _: MessageDTO = try await api.post("conversations/\(m.conversationID)/messages", body: body)
    }

    func conversationID(currentUserID: String, currentPhone: Int64, recipientID: String, recipientPhone: Int64) async throws -> String {
        struct Body: Encodable { let participantIds: [String] }
        let c: ConversationDTO = try await api.post("conversations", body: Body(participantIds: [recipientID]))
        lock.withLock { conversations[c.id] = c }
        return c.id
    }

    // MARK: Mapping

    private func loadConversationIfNeeded(_ id: String) async throws {
        if lock.withLock({ conversations[id] }) != nil { return }
        let c: ConversationDTO = try await api.get("conversations/\(id)")
        lock.withLock { conversations[id] = c }
    }

    private func noteOldest(_ id: String, _ seq: Int?) {
        guard let seq else { return }
        lock.withLock { oldestSeq[id] = min(oldestSeq[id] ?? .max, seq) }
    }

    private func phone(_ p: ParticipantDTO?) -> Int64 { Int64(p?.phoneNumber ?? "") ?? 0 }

    private func conversation(_ c: ConversationDTO, me: String) -> Conversation {
        let mine = c.participants.first { $0.id == me }
        let other = c.participants.first { $0.id != me }
        let sender = c.participants.first { $0.id == c.lastMessage?.senderId }
        return Conversation(
            id: c.id,
            participants: c.participants.map(\.id),
            lastMessage: c.lastMessage?.text ?? (c.lastMessage?.media.isEmpty == false ? "📷" : ""),
            lastSenderID: c.lastMessage?.senderId ?? "",
            lastType: Self.type(c.lastMessage?.type),
            updatedAt: c.lastMessageAt ?? c.createdAt,
            currentUserPhoneNumber: phone(mine),
            recipientUserPhoneNumber: phone(other),
            lastSenderPhoneNumber: phone(sender)
        )
    }

    private func message(_ m: MessageDTO) -> ChatMessage {
        let c = lock.withLock { conversations[m.conversationId] }
        let sender = c?.participants.first { $0.id == m.senderId }
        let recipient = c?.participants.first { $0.id != m.senderId }
        let media = m.media.first?.domain
        return ChatMessage(
            id: m.clientId,
            conversationID: m.conversationId,
            senderID: m.senderId,
            recipientID: recipient?.id ?? "",
            content: m.deleted ? "" : (m.text ?? ""),
            timestamp: m.createdAt,
            type: Self.type(m.type),
            mediaURL: (media?.urls["large"] ?? media?.urls["medium"] ?? media?.urls["poster"])?.absoluteString ?? "",
            senderPhoneNumber: phone(sender),
            recipientPhoneNumber: phone(recipient),
            seen: (recipient?.lastReadSeq ?? 0) >= m.seq,
            state: .sent
        )
    }

    private static func type(_ server: String?) -> String {
        switch server {
        case "IMAGE": return "image"
        case "VIDEO": return "video"
        default: return "text"
        }
    }
}

// MARK: - Feed (legacy protocol; the API feed UI uses SocialRepository)

final class APIFeedRepository: FeedRepository, @unchecked Sendable {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func observeFeed(ownerPhone: Int64, limit: Int) -> AsyncThrowingStream<[FeedPost], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        let page: PageDTO<PostDTO> = try await api.get("feed/following", query: ["limit": String(min(limit, 100))])
                        continuation.yield(page.items.map { FeedPost(id: $0.id, authorPhone: 0, content: $0.text ?? "", timestamp: $0.publishedAt ?? $0.createdAt) })
                    } catch {
                        Log.feed.error("feed refresh failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
                    }
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func publish(_ post: NewPost, recipientPhones: [Int64]) async throws {
        struct Body: Encodable { let clientId: String; let text: String; let audience: String }
        let _: PostDTO = try await api.post("posts", body: Body(clientId: post.id, text: post.content, audience: "CONTACTS"))
    }

    func setReaction(postID: String, userID: String, reaction: Reaction?) async throws {
        struct Body: Encodable { let type: String }
        if let reaction {
            let _: ReactionSummaryDTO = try await api.post("posts/\(postID)/reactions", body: Body(type: reaction == .like ? "LIKE" : "DISLIKE"))
        } else {
            let _: ReactionSummaryDTO = try await api.delete("posts/\(postID)/reactions")
        }
    }

    func reactionSummary(postID: String, userID: String) async throws -> ReactionSummary {
        let p: PostDTO = try await api.get("posts/\(postID)")
        let mine: Reaction? = p.viewer.reaction == "LIKE" ? .like : p.viewer.reaction == "DISLIKE" ? .dislike : nil
        return ReactionSummary(likes: p.counts.likes, dislikes: p.counts.dislikes, mine: mine)
    }
}

// MARK: - Media

/// Presigned direct upload to R2, then waits for server-side processing.
final class APIMediaRepository: MediaRepository, @unchecked Sendable {
    private let social: APISocialRepository
    init(social: APISocialRepository) { self.social = social }

    func uploadImage(_ data: Data, path: String, onProgress: (@Sendable (Double) -> Void)?) async throws -> UploadedMedia {
        let purpose: MediaPurpose = path.hasPrefix("avatars/") ? .avatar : .message
        let media = try await social.uploadMedia(data, mimeType: "image/jpeg", purpose: purpose, onProgress: onProgress)
        guard let url = media.urls["large"] ?? media.urls["medium"] ?? media.displayURL else {
            throw AppError.storage(underlying: "processed media has no URL")
        }
        return UploadedMedia(id: media.id, url: url.absoluteString)
    }

    /// Server-side cleanup removes media that is no longer referenced; nothing to do from the client.
    func delete(url: String) async throws {}
}

// MARK: - Safety

final class APISafetyRepository: SafetyRepository, @unchecked Sendable {
    private let api: APIClient
    private let refreshes = AsyncStream<Void>.makeStream()

    init(api: APIClient) { self.api = api }

    func block(_ user: BlockedUser, by userID: String) async throws {
        try await api.postEmpty("users/\(user.id)/block")
        refreshes.continuation.yield()
    }

    func unblock(userID: String, by blockerID: String) async throws {
        try await api.delete("users/\(userID)/block")
        refreshes.continuation.yield()
    }

    func observeBlockedUsers(for userID: String, limit: Int) -> AsyncThrowingStream<[BlockedUser], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let load = { [api] in
                    let page: PageDTO<BlockedDTO> = try await api.get("users/me/blocked", query: ["limit": String(min(limit, 100))])
                    continuation.yield(page.items.map { BlockedUser(id: $0.id, phoneNumber: 0, displayName: $0.displayName, blockedAt: $0.since) })
                }
                do { try await load() } catch { continuation.finish(throwing: error); return }
                for await _ in refreshes.stream { try? await load() }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func report(targetUserID: String, reporterID: String, reason: ReportReason, conversationID: String?, messageID: String?) async throws {
        struct Body: Encodable { let targetType: String; let targetId: String; let reason: String }
        struct Result: Decodable { let id: String }
        let body = messageID.map { Body(targetType: "MESSAGE", targetId: $0, reason: reason.rawValue.uppercased()) }
            ?? Body(targetType: "USER", targetId: targetUserID, reason: reason.rawValue.uppercased())
        let _: Result = try await api.post("reports", body: body)
    }
}

extension APIClient {
    /// POST without body or meaningful response (e.g. 204 actions).
    func postEmpty(_ path: String) async throws {
        let _: EmptyResponse = try await post(path)
    }
}

// MARK: - Social

final class APISocialRepository: SocialRepository, @unchecked Sendable {
    private let api: APIClient
    private let session: URLSession

    init(api: APIClient, session: URLSession = .shared) {
        self.api = api
        self.session = session
    }

    private func page(_ p: PageDTO<PostDTO>) -> Page<Post> { Page(items: p.items.map(\.domain), nextCursor: p.nextCursor) }

    func followingFeed(cursor: String?) async throws -> Page<Post> { page(try await api.get("feed/following", query: ["cursor": cursor])) }
    func discoverFeed(cursor: String?) async throws -> Page<Post> { page(try await api.get("feed/discover", query: ["cursor": cursor])) }
    func post(id: String) async throws -> Post { (try await api.get("posts/\(id)") as PostDTO).domain }

    func createPost(_ input: NewPostInput) async throws -> Post {
        struct Body: Encodable { let clientId: String; let text: String?; let mediaIds: [String]?; let audience: String }
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Body(clientId: input.clientID, text: text.isEmpty ? nil : text, mediaIds: input.mediaIDs.isEmpty ? nil : input.mediaIDs, audience: input.audience.rawValue)
        return (try await api.post("posts", body: body) as PostDTO).domain
    }

    func deletePost(id: String) async throws { try await api.delete("posts/\(id)") }

    func react(postID: String, _ reaction: ReactionKind?) async throws -> ReactionCounts {
        struct Body: Encodable { let type: String }
        if let reaction { return (try await api.post("posts/\(postID)/reactions", body: Body(type: reaction.rawValue)) as ReactionSummaryDTO).domain }
        return (try await api.delete("posts/\(postID)/reactions") as ReactionSummaryDTO).domain
    }

    func setSaved(postID: String, _ saved: Bool) async throws {
        struct Result: Decodable { let saved: Bool }
        if saved { let _: Result = try await api.post("posts/\(postID)/save") } else { let _: Result = try await api.delete("posts/\(postID)/save") }
    }

    func repost(postID: String) async throws { let _: PostDTO = try await api.post("posts/\(postID)/repost") }

    func reportImpressions(postIDs: [String]) async {
        struct Body: Encodable { let postIds: [String] }
        struct Result: Decodable { let accepted: Int }
        guard !postIDs.isEmpty else { return }
        let _: Result? = try? await api.post("feed/impressions", body: Body(postIds: Array(postIDs.prefix(50))))
    }

    func comments(postID: String, cursor: String?) async throws -> Page<Comment> {
        let p: PageDTO<CommentDTO> = try await api.get("posts/\(postID)/comments", query: ["cursor": cursor])
        return Page(items: p.items.map(\.domain), nextCursor: p.nextCursor)
    }

    func replies(commentID: String, cursor: String?) async throws -> Page<Comment> {
        let p: PageDTO<CommentDTO> = try await api.get("comments/\(commentID)/replies", query: ["cursor": cursor])
        return Page(items: p.items.map(\.domain), nextCursor: p.nextCursor)
    }

    func addComment(postID: String, text: String, parentID: String?, clientID: String) async throws -> Comment {
        struct Body: Encodable { let text: String; let parentId: String?; let clientId: String }
        return (try await api.post("posts/\(postID)/comments", body: Body(text: text, parentId: parentID, clientId: clientID)) as CommentDTO).domain
    }

    func deleteComment(id: String) async throws { try await api.delete("comments/\(id)") }

    func reactToComment(id: String, _ reaction: ReactionKind?) async throws -> ReactionCounts {
        struct Body: Encodable { let type: String }
        if let reaction { return (try await api.post("comments/\(id)/reactions", body: Body(type: reaction.rawValue)) as ReactionSummaryDTO).domain }
        return (try await api.delete("comments/\(id)/reactions") as ReactionSummaryDTO).domain
    }

    func profile(userID: String) async throws -> Profile { (try await api.get("users/id/\(userID)") as ProfileDTO).domain }

    func posts(by userID: String, cursor: String?) async throws -> Page<Post> {
        struct Result: Decodable { let items: [PostDTO]; let nextCursor: String?; let pinned: PostDTO? }
        let r: Result = try await api.get("users/\(userID)/posts", query: ["cursor": cursor])
        let items = (r.pinned.map { [$0] } ?? []) + r.items
        return Page(items: items.map(\.domain), nextCursor: r.nextCursor)
    }

    func follow(userID: String) async throws -> FollowState {
        struct Result: Decodable { let state: String }
        let r: Result = try await api.post("users/\(userID)/follow")
        return FollowState(rawValue: r.state) ?? .none
    }

    func unfollow(userID: String) async throws {
        struct Result: Decodable { let state: String }
        let _: Result = try await api.delete("users/\(userID)/follow")
    }

    func searchUsers(_ query: String, cursor: String?) async throws -> Page<UserSummary> {
        let p: PageDTO<UserSummaryDTO> = try await api.get("search/users", query: ["q": query, "cursor": cursor])
        return Page(items: p.items.map(\.domain), nextCursor: p.nextCursor)
    }

    func searchPosts(_ query: String, cursor: String?) async throws -> Page<Post> {
        page(try await api.get("search/posts", query: ["q": query, "cursor": cursor]))
    }

    func trendingHashtags() async throws -> [String] {
        struct Tag: Decodable { let tag: String }
        struct Result: Decodable { let items: [Tag] }
        return (try await api.get("search/hashtags/trending", query: ["limit": "10"]) as Result).items.map(\.tag)
    }

    func activity(cursor: String?) async throws -> Page<ActivityItem> {
        let p: PageDTO<NotificationDTO> = try await api.get("notifications", query: ["cursor": cursor])
        return Page(items: p.items.compactMap(\.domain), nextCursor: p.nextCursor)
    }

    func unreadActivityCount() async throws -> Int {
        struct Result: Decodable { let unread: Int }
        return (try await api.get("notifications/unread-count") as Result).unread
    }

    func markActivityRead(id: String?) async throws {
        if let id {
            let _: EmptyResponse = try await api.patch("notifications/\(id)/read", body: [String: String]())
        } else {
            struct Result: Decodable { let updated: Int }
            let _: Result = try await api.patch("notifications/read-all", body: [String: String]())
        }
    }

    /// 1) ask for a presigned URL, 2) PUT the bytes straight to storage, 3) confirm, 4) wait for processing.
    func uploadMedia(_ data: Data, mimeType: String, purpose: MediaPurpose, onProgress: (@Sendable (Double) -> Void)?) async throws -> MediaItem {
        struct TicketBody: Encodable { let purpose: String; let mimeType: String; let sizeBytes: Int }
        struct CompleteBody: Encodable { let mediaId: String }
        let ticket: UploadTicketDTO = try await api.post("media/upload-url", body: TicketBody(purpose: purpose.rawValue, mimeType: mimeType, sizeBytes: data.count))
        guard let url = URL(string: ticket.uploadUrl) else { throw AppError.storage(underlying: "bad upload URL") }
        var request = URLRequest(url: url)
        request.httpMethod = ticket.method
        for (k, v) in ticket.headers where k.lowercased() != "content-length" { request.setValue(v, forHTTPHeaderField: k) }
        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let (_, response) = try await session.upload(for: request, from: data, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.storage(underlying: "upload failed")
        }
        onProgress?(0.95)
        var media: MediaDTO = try await api.post("media/complete", body: CompleteBody(mediaId: ticket.mediaId))
        let deadline = Date().addingTimeInterval(purpose == .post && mimeType.hasPrefix("video/") ? 600 : 60)
        while media.status == MediaStatus.processing.rawValue, Date() < deadline {
            try await Task.sleep(for: .milliseconds(800))
            media = try await api.get("media/\(ticket.mediaId)")
        }
        onProgress?(1)
        switch MediaStatus(rawValue: media.status) {
        case .ready: return media.domain
        case .failed: throw AppError.validation(String(localized: "media.failed", defaultValue: "This file couldn't be processed."))
        default:
            // Still processing (long video): the post can reference it; it appears when ready.
            return media.domain
        }
    }
}

/// Reports bytes sent for one upload task (0...0.95; the rest is server-side processing).
final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: (@Sendable (Double) -> Void)?
    init(onProgress: (@Sendable (Double) -> Void)?) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress?(0.95 * Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
