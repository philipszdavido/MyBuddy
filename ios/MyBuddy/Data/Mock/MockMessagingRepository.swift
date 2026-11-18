//
//  MockMessagingRepository.swift
//  MyBuddy
//
//  In-memory MessagingRepository / AccountRepository for previews, unit tests and UI tests.
//

import Foundation

final class MockMessagingRepository: MessagingRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var conversationsByID: [String: ChatConversation] = [:]
    private var messagesByConversation: [String: [ChatItem]] = [:]
    private var continuations: [UUID: AsyncStream<ChatEvent>.Continuation] = [:]
    static let me = MockSocialRepository.me
    static let ada = MockSocialRepository.ada
    static let bola = UserSummary(id: "bola", username: "bola", displayName: "Bola", avatarURL: nil, isVerified: false)

    init(seed: Bool = true) {
        guard seed else { return }
        let now = Date()
        let direct = ChatConversation(id: "c-ada", kind: .direct, title: nil,
                                      participants: [.init(user: Self.me, isAdmin: false, lastReadSeq: 1), .init(user: Self.ada, isAdmin: false, lastReadSeq: 2)],
                                      lastMessage: nil, lastSeq: 2, unreadCount: 1, isRequest: false, muted: false, lastActivity: now)
        let request = ChatConversation(id: "c-bola", kind: .direct, title: nil,
                                       participants: [.init(user: Self.me, isAdmin: false, lastReadSeq: 0), .init(user: Self.bola, isAdmin: false, lastReadSeq: 1)],
                                       lastMessage: nil, lastSeq: 1, unreadCount: 1, isRequest: true, muted: false, lastActivity: now.addingTimeInterval(-600))
        conversationsByID = [direct.id: direct, request.id: request]
        messagesByConversation[direct.id] = [
            item("c-ada", 1, Self.me, "Hi Ada!", now.addingTimeInterval(-300)),
            item("c-ada", 2, Self.ada, "Hey! How are you?", now.addingTimeInterval(-60)),
        ]
        messagesByConversation[request.id] = [item("c-bola", 1, Self.bola, "Hello, we met at the conference.", now.addingTimeInterval(-600))]
        for (id, list) in messagesByConversation { conversationsByID[id]?.lastMessage = list.last }
    }

    private func item(_ conversation: String, _ seq: Int, _ sender: UserSummary, _ text: String, _ date: Date) -> ChatItem {
        ChatItem(id: "\(conversation)-\(seq)", clientID: "\(conversation)-\(seq)", conversationID: conversation, seq: seq, sender: sender, senderID: sender.id,
                 kind: .text, text: text, media: [], replyToText: nil, reactions: [:], edited: false, deleted: false, createdAt: date)
    }

    private func emit(_ event: ChatEvent) { lock.withLock { Array(continuations.values) }.forEach { $0.yield(event) } }

    func currentUserID() async throws -> String { Self.me.id }

    func conversations(requests: Bool, cursor: String?) async throws -> Page<ChatConversation> {
        lock.withLock { Page(items: conversationsByID.values.filter { $0.isRequest == requests }.sorted { $0.lastActivity > $1.lastActivity }, nextCursor: nil) }
    }

    func conversation(id: String) async throws -> ChatConversation {
        guard let c = lock.withLock({ conversationsByID[id] }) else { throw AppError.notFound }
        return c
    }

    func messages(conversationID: String, beforeSeq: Int?, afterSeq: Int?) async throws -> (items: [ChatItem], hasMore: Bool) {
        let all = lock.withLock { messagesByConversation[conversationID] ?? [] }
        if let afterSeq { return (all.filter { $0.seq > afterSeq }, false) }
        return (all.filter { $0.seq < (beforeSeq ?? .max) }.reversed(), false)
    }

    func send(conversationID: String, clientID: String, text: String?, mediaIDs: [String]) async throws -> ChatItem {
        let message = try lock.withLock { () -> ChatItem in
            guard var c = conversationsByID[conversationID] else { throw AppError.notFound }
            if let existing = messagesByConversation[conversationID]?.first(where: { $0.clientID == clientID }) { return existing }
            c.lastSeq += 1
            let m = ChatItem(id: UUID().uuidString, clientID: clientID, conversationID: conversationID, seq: c.lastSeq, sender: Self.me, senderID: Self.me.id,
                             kind: mediaIDs.isEmpty ? .text : .image, text: text, media: [], replyToText: nil, reactions: [:], edited: false, deleted: false, createdAt: Date())
            messagesByConversation[conversationID, default: []].append(m)
            c.lastMessage = m
            c.lastActivity = m.createdAt
            c.isRequest = false
            conversationsByID[conversationID] = c
            return m
        }
        emit(.message(message))
        return message
    }

    func startConversation(with userIDs: [String], title: String?) async throws -> ChatConversation {
        lock.withLock {
            let people = [Self.ada, Self.bola].filter { userIDs.contains($0.id) }
            if people.count == 1, let existing = conversationsByID.values.first(where: { $0.kind == .direct && $0.others(Self.me.id).first?.id == people[0].id }) {
                return existing
            }
            let c = ChatConversation(id: UUID().uuidString, kind: people.count > 1 ? .group : .direct, title: title,
                                     participants: [.init(user: Self.me, isAdmin: true, lastReadSeq: 0)] + people.map { .init(user: $0, isAdmin: false, lastReadSeq: 0) },
                                     lastMessage: nil, lastSeq: 0, unreadCount: 0, isRequest: false, muted: false, lastActivity: Date())
            conversationsByID[c.id] = c
            return c
        }
    }

    func accept(conversationID: String) async throws { lock.withLock { conversationsByID[conversationID]?.isRequest = false } }
    func leave(conversationID: String) async throws { lock.withLock { _ = conversationsByID.removeValue(forKey: conversationID) } }

    func rename(conversationID: String, title: String) async throws -> ChatConversation {
        try lock.withLock {
            guard conversationsByID[conversationID] != nil else { throw AppError.notFound }
            conversationsByID[conversationID]?.title = title
            return conversationsByID[conversationID]!
        }
    }

    func setMuted(conversationID: String, _ muted: Bool) async throws { lock.withLock { conversationsByID[conversationID]?.muted = muted } }

    func addMembers(conversationID: String, userIDs: [String]) async throws -> ChatConversation {
        try lock.withLock {
            guard var c = conversationsByID[conversationID] else { throw AppError.notFound }
            for user in [Self.ada, Self.bola] where userIDs.contains(user.id) && !c.participants.contains(where: { $0.id == user.id }) {
                c.participants.append(.init(user: user, isAdmin: false, lastReadSeq: c.lastSeq))
            }
            conversationsByID[conversationID] = c
            return c
        }
    }

    func removeMember(conversationID: String, userID: String) async throws {
        lock.withLock { conversationsByID[conversationID]?.participants.removeAll { $0.id == userID } }
    }

    func markRead(conversationID: String, seq: Int) async { lock.withLock { conversationsByID[conversationID]?.unreadCount = 0 } }

    func deleteMessage(id: String) async throws {
        lock.withLock {
            for (c, list) in messagesByConversation {
                if let i = list.firstIndex(where: { $0.id == id }) { messagesByConversation[c]?[i].deleted = true; messagesByConversation[c]?[i].text = nil }
            }
        }
    }

    func typing(conversationID: String, isTyping: Bool) {}

    func events() -> AsyncStream<ChatEvent> {
        AsyncStream { c in
            let id = UUID()
            lock.withLock { continuations[id] = c }
            c.yield(.connected)
            c.onTermination = { [weak self] _ in _ = self?.lock.withLock { self?.continuations.removeValue(forKey: id) } }
        }
    }

    func contacts() async throws -> [UserSummary] { [Self.ada, Self.bola] }
    func requestCount() async throws -> Int { lock.withLock { conversationsByID.values.filter(\.isRequest).count } }
}

final class MockAccountRepository: AccountRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var profile = AccountProfile(
        id: "me", username: "me", displayName: "Me", bio: "Building MyBuddy.", location: "Lagos", website: nil, avatarURL: nil,
        visibility: .public, email: "me@example.com", phoneNumber: "2348000000000", phoneVerified: false,
        settings: PrivacySettings(showActivityStatus: true, sendReadReceipts: true, allowMessagesFrom: .everyone, discoverable: true),
        followersCount: 12, followingCount: 8, postsCount: 3
    )
    private var preferences: [ActivityType: NotificationPreference] = [:]
    let takenUsernames: Set<String> = ["ada", "bola", "admin"]

    func me() async throws -> AccountProfile { lock.withLock { profile } }

    func update(_ c: ProfileChanges) async throws -> AccountProfile {
        try lock.withLock {
            if let u = c.username?.lowercased(), u != profile.username {
                guard u.range(of: "^[a-z0-9_.]{3,30}$", options: .regularExpression) != nil else { throw AppError.validation("Invalid username") }
                guard !takenUsernames.contains(u) else { throw AppError.validation("That username is taken") }
                profile.username = u
            }
            if let v = c.displayName { profile.displayName = v }
            if let v = c.bio { profile.bio = v.isEmpty ? nil : v }
            if let v = c.location { profile.location = v.isEmpty ? nil : v }
            if let v = c.website { profile.website = v.isEmpty ? nil : v }
            if let v = c.visibility { profile.visibility = v }
            return profile
        }
    }

    func usernameStatus(_ username: String) async throws -> UsernameStatus {
        let u = username.lowercased()
        guard u.range(of: "^[a-z0-9_.]{3,30}$", options: .regularExpression) != nil else { return .invalid }
        return takenUsernames.contains(u) ? .taken : .available
    }

    func updatePrivacy(_ settings: PrivacySettings) async throws -> AccountProfile { lock.withLock { profile.settings = settings; return profile } }

    func setAvatar(_ jpeg: Data, onProgress: @escaping @Sendable (Double) -> Void) async throws -> AccountProfile {
        for step in 1...4 { onProgress(Double(step) / 4); try await Task.sleep(for: .milliseconds(80)) }
        return lock.withLock { profile }
    }

    func removeAvatar() async throws -> AccountProfile { lock.withLock { profile.avatarURL = nil; return profile } }

    func notificationPreferences() async throws -> [NotificationPreference] {
        let all: [ActivityType] = [.message, .messageRequest, .follow, .followRequest, .followAccepted, .postReaction, .comment, .commentReply, .commentReaction, .mention, .repost]
        return lock.withLock { all.map { preferences[$0] ?? NotificationPreference(type: $0, push: true, inApp: true) } }
    }

    func setNotificationPreference(_ preference: NotificationPreference) async throws { lock.withLock { preferences[preference.type] = preference } }
}
