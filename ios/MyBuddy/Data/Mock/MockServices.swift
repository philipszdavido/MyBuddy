//
//  MockServices.swift
//  MyBuddy
//
//  In-memory implementations for unit tests, previews and UI tests (MBUITesting=1).
//

import Foundation

final class MockAuthenticationService: AuthenticationService, @unchecked Sendable {
    private let lock = NSLock()
    private var user: AuthUser?
    private var accounts: [String: String] = [:]          // email -> password
    private var continuations: [UUID: AsyncStream<AuthUser?>.Continuation] = [:]
    var signInError: AppError?
    private(set) var deleteCalled = false

    init(signedIn: AuthUser? = nil) { self.user = signedIn }

    var currentUser: AuthUser? { lock.withLock { user } }

    private func publish(_ new: AuthUser?) {
        let conts = lock.withLock { user = new; return Array(continuations.values) }
        conts.forEach { $0.yield(new) }
    }

    func authStateChanges() -> AsyncStream<AuthUser?> {
        AsyncStream { c in
            let id = UUID()
            lock.withLock { continuations[id] = c }
            c.yield(currentUser)
            c.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.lock.withLock { self.continuations.removeValue(forKey: id) }
            }
        }
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        if let signInError { throw signInError }
        guard lock.withLock({ accounts[email] }) == password else { throw AppError.authentication(.invalidCredentials) }
        let u = AuthUser(id: "uid-\(email)", email: email, isEmailVerified: true)
        publish(u)
        return u
    }

    func reauthenticate(password: String) async throws {
        guard let email = currentUser?.email else { throw AppError.authentication(.notSignedIn) }
        guard lock.withLock({ accounts[email] }) == password else { throw AppError.authentication(.invalidCredentials) }
    }

    func register(email: String, password: String) async throws -> AuthUser {
        guard lock.withLock({ accounts[email] }) == nil else { throw AppError.authentication(.emailInUse) }
        guard password.count >= 6 else { throw AppError.authentication(.weakPassword) }
        lock.withLock { accounts[email] = password }
        let u = AuthUser(id: "uid-\(email)", email: email, isEmailVerified: false)
        publish(u)
        return u
    }

    func sendPasswordReset(email: String) async throws {}
    func sendEmailVerification() async throws {}
    func idToken(forceRefresh: Bool) async throws -> String {
        guard let user = currentUser else { throw AppError.authentication(.notSignedIn) }
        return "mock-token-\(user.id)"
    }
    func signOut() throws { publish(nil) }
    func deleteAccount() async throws {
        guard currentUser != nil else { throw AppError.authentication(.notSignedIn) }
        lock.withLock { deleteCalled = true }
        publish(nil)
    }
}

final class MockUserRepository: UserRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: UserAccount]

    init(_ seed: [UserAccount] = []) { store = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) }) }

    func account(id: String) async throws -> UserAccount? { lock.withLock { store[id] } }
    func save(_ account: UserAccount) async throws { lock.withLock { store[account.id] = account } }
    func updatePhoto(id: String, media: UploadedMedia?) async throws {
        lock.withLock { store[id]?.photoURL = media?.url }
    }
    func syncContacts(phoneNumbers numbers: [Int64]) async throws -> [UserAccount] {
        try await accounts(matchingPhoneNumbers: numbers)
    }
    func accounts(matchingPhoneNumbers numbers: [Int64]) async throws -> [UserAccount] {
        let set = Set(numbers)
        return lock.withLock { store.values.filter { set.contains($0.phoneNumber) } }
    }
}

final class MockChatRepository: ChatRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var messagesByChat: [String: [ChatMessage]] = [:]   // keyed by id inside, newest-first on read
    private var observers: [UUID: (String, AsyncThrowingStream<[ChatMessage], Error>.Continuation, Int)] = [:]
    var sendError: AppError?
    private(set) var sendAttempts = 0
    private(set) var activeMessageObservers = 0

    func observeConversations(userID: String, limit: Int) -> AsyncThrowingStream<[Conversation], Error> {
        AsyncThrowingStream { $0.yield([]) }
    }

    private func sorted(_ chat: String) -> [ChatMessage] {
        (messagesByChat[chat] ?? []).sorted { $0.timestamp > $1.timestamp }
    }

    func observeLatestMessages(conversationID: String, limit: Int) -> AsyncThrowingStream<[ChatMessage], Error> {
        AsyncThrowingStream { c in
            let id = UUID()
            let initial: [ChatMessage] = lock.withLock {
                observers[id] = (conversationID, c, limit)
                activeMessageObservers += 1
                return Array(sorted(conversationID).prefix(limit))
            }
            c.yield(initial)
            c.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { _ = self.observers.removeValue(forKey: id); self.activeMessageObservers -= 1 }
            }
        }
    }

    func loadOlderMessages(conversationID: String, before cursor: MessageCursor, limit: Int) async throws -> MessagePage {
        let older = lock.withLock { sorted(conversationID).filter { $0.timestamp < cursor.timestamp } }
        let page = Array(older.prefix(limit))
        let next = page.count == limit ? page.last.map { MessageCursor(timestamp: $0.timestamp, id: $0.id) } : nil
        return MessagePage(messages: page, nextCursor: next)
    }

    func conversationID(currentUserID: String, currentPhone: Int64, recipientID: String, recipientPhone: Int64) async throws -> String {
        [String(currentPhone), String(recipientPhone)].sorted().joined(separator: "_")
    }

    func send(_ m: OutgoingMessage) async throws {
        let targets: [(AsyncThrowingStream<[ChatMessage], Error>.Continuation, [ChatMessage])] = try lock.withLock {
            sendAttempts += 1
            if let sendError { throw sendError }
            var list = messagesByChat[m.conversationID] ?? []
            list.removeAll { $0.id == m.id }                      // idempotent
            list.append(ChatMessage(id: m.id, conversationID: m.conversationID, senderID: m.senderID,
                                    recipientID: m.recipientID, content: m.content, timestamp: Date(),
                                    type: m.type, mediaURL: m.mediaURL, senderPhoneNumber: m.senderPhoneNumber,
                                    recipientPhoneNumber: m.recipientPhoneNumber, seen: false, state: .sent))
            messagesByChat[m.conversationID] = list
            return observers.values.filter { $0.0 == m.conversationID }
                .map { ($0.1, Array(sorted(m.conversationID).prefix($0.2))) }
        }
        targets.forEach { $0.0.yield($0.1) }
    }

    func messageCount(_ chat: String) -> Int { lock.withLock { messagesByChat[chat]?.count ?? 0 } }
}

final class MockFeedRepository: FeedRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var feeds: [Int64: [String: FeedPost]] = [:]          // phone -> postId -> post
    private var reactions: [String: [String: Reaction]] = [:]     // postId -> userId -> reaction
    var publishError: AppError?
    private(set) var publishAttempts = 0

    func observeFeed(ownerPhone: Int64, limit: Int) -> AsyncThrowingStream<[FeedPost], Error> {
        let posts = lock.withLock {
            Array((feeds[ownerPhone] ?? [:]).values.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
        }
        return AsyncThrowingStream { $0.yield(posts) }
    }

    func publish(_ post: NewPost, recipientPhones: [Int64]) async throws {
        try lock.withLock {
            publishAttempts += 1
            if let publishError { throw publishError }
            let value = FeedPost(id: post.id, authorPhone: post.authorPhone, content: post.content, timestamp: Date())
            for phone in Set(recipientPhones + [post.authorPhone]) {
                feeds[phone, default: [:]][post.id] = value      // same id => overwrite, no duplicates
            }
        }
    }

    func setReaction(postID: String, userID: String, reaction: Reaction?) async throws {
        lock.withLock { reactions[postID, default: [:]][userID] = reaction }
    }

    func reactionSummary(postID: String, userID: String) async throws -> ReactionSummary {
        lock.withLock {
            let r = reactions[postID] ?? [:]
            return ReactionSummary(likes: r.values.filter { $0 == .like }.count,
                                   dislikes: r.values.filter { $0 == .dislike }.count,
                                   mine: r[userID])
        }
    }

    func copies(of postID: String) -> Int { lock.withLock { feeds.values.filter { $0[postID] != nil }.count } }
}

final class MockPushNotificationService: PushNotificationService, @unchecked Sendable {
    private let lock = NSLock()
    private var registered = Set<String>()
    var grantsAuthorization = true

    func requestAuthorization() async throws -> Bool { grantsAuthorization }
    func registerDevice(userID: String) async throws { lock.withLock { _ = registered.insert(userID) } }
    func unregisterDevice(userID: String) async throws { lock.withLock { _ = registered.remove(userID) } }
    func isRegistered(_ userID: String) -> Bool { lock.withLock { registered.contains(userID) } }
}

final class MockMediaRepository: MediaRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: Data] = [:]
    private var deletedURLs: [String] = []
    var failuresRemaining = 0

    func uploadImage(_ data: Data, path: String, onProgress: (@Sendable (Double) -> Void)?) async throws -> UploadedMedia {
        try lock.withLock {
            if failuresRemaining > 0 { failuresRemaining -= 1; throw AppError.network(underlying: "offline") }
            stored[path] = data     // same path overwrites
        }
        onProgress?(1)
        return UploadedMedia(id: path, url: "https://mock.test/\(path)")
    }

    func delete(url: String) async throws { lock.withLock { deletedURLs.append(url) } }

    func data(at path: String) -> Data? { lock.withLock { stored[path] } }
    var storedCount: Int { lock.withLock { stored.count } }
    var deleted: [String] { lock.withLock { deletedURLs } }
}

final class MockSafetyRepository: SafetyRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var blocked: [String: [String: BlockedUser]] = [:]   // blocker -> blocked -> user
    private var reports: [[String: String]] = []

    func block(_ user: BlockedUser, by userID: String) async throws {
        lock.withLock { blocked[userID, default: [:]][user.id] = user }
    }

    func unblock(userID: String, by blockerID: String) async throws {
        _ = lock.withLock { blocked[blockerID]?.removeValue(forKey: userID) }
    }

    func observeBlockedUsers(for userID: String, limit: Int) -> AsyncThrowingStream<[BlockedUser], Error> {
        let current = lock.withLock { Array((blocked[userID] ?? [:]).values.prefix(limit)) }
        return AsyncThrowingStream { $0.yield(current) }
    }

    func report(targetUserID: String, reporterID: String, reason: ReportReason,
                conversationID: String?, messageID: String?) async throws {
        lock.withLock {
            reports.append(["target": targetUserID, "reporter": reporterID, "reason": reason.rawValue])
        }
    }

    var reportCount: Int { lock.withLock { reports.count } }
}
