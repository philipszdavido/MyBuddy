//
//  APIMessagingRepository.swift
//  MyBuddy
//
//  MessagingRepository and AccountRepository over the MyBuddy API. Live updates come from the shared
//  RealtimeClient; REST is the source of truth after every reconnect.
//

import Foundation

final class APIMessagingRepository: MessagingRepository, @unchecked Sendable {
    private let api: APIClient
    private let realtime: RealtimeClient
    private let decoder = APIClient.makeDecoder()
    private let lock = NSLock()
    private var meID: String?

    init(api: APIClient, realtime: RealtimeClient) {
        self.api = api
        self.realtime = realtime
    }

    func currentUserID() async throws -> String {
        if let id = lock.withLock({ meID }) { return id }
        let me: MeDTO = try await api.get("users/me")
        lock.withLock { meID = me.id }
        return me.id
    }

    func conversations(requests: Bool, cursor: String?) async throws -> Page<ChatConversation> {
        let page: PageDTO<ConversationDTO> = try await api.get("conversations", query: ["requests": requests ? "true" : nil, "cursor": cursor, "limit": "50"])
        return Page(items: page.items.map(\.domain), nextCursor: page.nextCursor)
    }

    func conversation(id: String) async throws -> ChatConversation { (try await api.get("conversations/\(id)") as ConversationDTO).domain }

    func messages(conversationID: String, beforeSeq: Int?, afterSeq: Int?) async throws -> (items: [ChatItem], hasMore: Bool) {
        let page: MessagesPageDTO = try await api.get("conversations/\(conversationID)/messages",
                                                     query: ["beforeSeq": beforeSeq.map(String.init), "afterSeq": afterSeq.map(String.init), "limit": "50"])
        return (page.items.map(\.domain), page.hasMore)
    }

    func send(conversationID: String, clientID: String, text: String?, mediaIDs: [String]) async throws -> ChatItem {
        struct Body: Encodable { let clientId: String; let text: String?; let mediaIds: [String]? }
        let m: MessageDTO = try await api.post("conversations/\(conversationID)/messages",
                                               body: Body(clientId: clientID, text: text, mediaIds: mediaIDs.isEmpty ? nil : mediaIDs))
        return m.domain
    }

    func startConversation(with userIDs: [String], title: String?) async throws -> ChatConversation {
        struct Body: Encodable { let participantIds: [String]; let title: String? }
        return (try await api.post("conversations", body: Body(participantIds: userIDs, title: title)) as ConversationDTO).domain
    }

    func accept(conversationID: String) async throws { let _: ConversationDTO = try await api.post("conversations/\(conversationID)/accept") }
    func leave(conversationID: String) async throws { try await api.delete("conversations/\(conversationID)") }

    func rename(conversationID: String, title: String) async throws -> ChatConversation {
        struct Body: Encodable { let title: String }
        return (try await api.patch("conversations/\(conversationID)", body: Body(title: title)) as ConversationDTO).domain
    }

    func setMuted(conversationID: String, _ muted: Bool) async throws {
        struct Body: Encodable {
            let mutedUntil: String?
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(mutedUntil, forKey: .mutedUntil) // explicit null unmutes
            }
            enum CodingKeys: String, CodingKey { case mutedUntil }
        }
        let until = muted ? Date().addingTimeInterval(10 * 365 * 86400).ISO8601Format() : nil
        let _: ConversationDTO = try await api.patch("conversations/\(conversationID)", body: Body(mutedUntil: until))
    }

    func addMembers(conversationID: String, userIDs: [String]) async throws -> ChatConversation {
        struct Body: Encodable { let userIds: [String] }
        return (try await api.post("conversations/\(conversationID)/participants", body: Body(userIds: userIDs)) as ConversationDTO).domain
    }

    func removeMember(conversationID: String, userID: String) async throws {
        try await api.delete("conversations/\(conversationID)/participants/\(userID)")
    }

    func markRead(conversationID: String, seq: Int) async {
        struct Body: Encodable { let seq: Int }
        struct Result: Decodable { let lastReadSeq: Int }
        let _: Result? = try? await api.post("conversations/\(conversationID)/read", body: Body(seq: seq))
    }

    func deleteMessage(id: String) async throws { try await api.delete("messages/\(id)") }

    func typing(conversationID: String, isTyping: Bool) {
        realtime.emit("typing", ["conversationId": conversationID, "isTyping": isTyping])
    }

    func events() -> AsyncStream<ChatEvent> {
        let signals = realtime.signals()
        let decoder = self.decoder
        return AsyncStream { continuation in
            let task = Task {
                for await signal in signals {
                    switch signal {
                    case .connected: continuation.yield(.connected)
                    case .disconnected: break
                    case .event(let name, let payload):
                        if let event = Self.map(name, payload, decoder) { continuation.yield(event) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func map(_ name: String, _ payload: Data, _ decoder: JSONDecoder) -> ChatEvent? {
        struct IDs: Decodable { let conversationId: String; let messageId: String?; let userId: String?; let seq: Int?; let isTyping: Bool? }
        switch name {
        case "message:new", "message:updated":
            return (try? decoder.decode(MessageDTO.self, from: payload)).map { .message($0.domain) }
        default:
            guard let ids = try? decoder.decode(IDs.self, from: payload) else { return nil }
            switch name {
            case "message:deleted": return ids.messageId.map { .messageDeleted(conversationID: ids.conversationId, messageID: $0) }
            case "conversation:updated", "message:reaction": return .conversationChanged(ids.conversationId)
            case "conversation:read":
                guard let user = ids.userId, let seq = ids.seq else { return nil }
                return .read(conversationID: ids.conversationId, userID: user, seq: seq)
            case "typing":
                guard let user = ids.userId else { return nil }
                return .typing(conversationID: ids.conversationId, userID: user, isTyping: ids.isTyping ?? false)
            default: return nil
            }
        }
    }

    func contacts() async throws -> [UserSummary] {
        let page: PageDTO<UserSummaryDTO> = try await api.get("contacts", query: ["limit": "100"])
        return page.items.map(\.domain)
    }

    func requestCount() async throws -> Int {
        let page: PageDTO<ConversationDTO> = try await api.get("conversations", query: ["requests": "true", "limit": "100"])
        return page.items.count
    }
}

// MARK: - Account

private struct AccountDTO: Decodable, Sendable {
    struct Settings: Decodable, Sendable {
        let showActivityStatus: Bool
        let sendReadReceipts: Bool
        let allowMessagesFrom: String
        let discoverable: Bool
    }
    let id: String
    let username: String?
    let displayName: String
    let bio: String?
    let location: String?
    let website: String?
    let avatarUrl: String?
    let visibility: String
    let email: String?
    let phoneNumber: String?
    let phoneVerified: Bool
    let followersCount: Int
    let followingCount: Int
    let postsCount: Int
    let settings: Settings

    var domain: AccountProfile {
        AccountProfile(
            id: id, username: username, displayName: displayName, bio: bio, location: location, website: website,
            avatarURL: avatarUrl.flatMap(URL.init(string:)), visibility: AccountVisibility(rawValue: visibility) ?? .public,
            email: email, phoneNumber: phoneNumber, phoneVerified: phoneVerified,
            settings: PrivacySettings(showActivityStatus: settings.showActivityStatus, sendReadReceipts: settings.sendReadReceipts,
                                      allowMessagesFrom: MessagePermission(rawValue: settings.allowMessagesFrom) ?? .everyone,
                                      discoverable: settings.discoverable),
            followersCount: followersCount, followingCount: followingCount, postsCount: postsCount
        )
    }
}

final class APIAccountRepository: AccountRepository, @unchecked Sendable {
    private let api: APIClient
    private let social: APISocialRepository

    init(api: APIClient, social: APISocialRepository) {
        self.api = api
        self.social = social
    }

    func me() async throws -> AccountProfile { (try await api.get("users/me") as AccountDTO).domain }

    /// nil = leave unchanged; "" = clear (sent as JSON null, which the server stores as "no value").
    func update(_ c: ProfileChanges) async throws -> AccountProfile {
        struct Body: Encodable {
            let changes: ProfileChanges
            enum CodingKeys: String, CodingKey { case username, displayName, bio, location, website, visibility }
            func encode(to encoder: Encoder) throws {
                var k = encoder.container(keyedBy: CodingKeys.self)
                func put(_ value: String?, _ key: CodingKeys) throws {
                    guard let value else { return }
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { try k.encodeNil(forKey: key) } else { try k.encode(trimmed, forKey: key) }
                }
                try k.encodeIfPresent(changes.username?.lowercased(), forKey: .username)
                try k.encodeIfPresent(changes.displayName, forKey: .displayName)
                try put(changes.bio, .bio)
                try put(changes.location, .location)
                try put(changes.website, .website)
                try k.encodeIfPresent(changes.visibility?.rawValue, forKey: .visibility)
            }
        }
        return (try await api.patch("users/me", body: Body(changes: c)) as AccountDTO).domain
    }

    func usernameStatus(_ username: String) async throws -> UsernameStatus {
        struct Result: Decodable { let available: Bool }
        let normalized = username.lowercased()
        guard normalized.range(of: "^[a-z0-9_.]{3,30}$", options: .regularExpression) != nil else { return .invalid }
        let r: Result = try await api.get("users/username-available", query: ["username": normalized])
        return r.available ? .available : .taken
    }

    func updatePrivacy(_ s: PrivacySettings) async throws -> AccountProfile {
        struct Body: Encodable { let showActivityStatus: Bool; let sendReadReceipts: Bool; let allowMessagesFrom: String; let discoverable: Bool }
        let body = Body(showActivityStatus: s.showActivityStatus, sendReadReceipts: s.sendReadReceipts,
                        allowMessagesFrom: s.allowMessagesFrom.rawValue, discoverable: s.discoverable)
        return (try await api.patch("users/me/settings", body: body) as AccountDTO).domain
    }

    func setAvatar(_ jpeg: Data, onProgress: @escaping @Sendable (Double) -> Void) async throws -> AccountProfile {
        let media = try await social.uploadMedia(jpeg, mimeType: "image/jpeg", purpose: .avatar, onProgress: onProgress)
        struct Body: Encodable { let avatarMediaId: String }
        return (try await api.patch("users/me", body: Body(avatarMediaId: media.id)) as AccountDTO).domain
    }

    func removeAvatar() async throws -> AccountProfile {
        struct Body: Encodable {
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeNil(forKey: .avatarMediaId)
            }
            enum CodingKeys: String, CodingKey { case avatarMediaId }
        }
        return (try await api.patch("users/me", body: Body()) as AccountDTO).domain
    }

    func notificationPreferences() async throws -> [NotificationPreference] {
        struct Pref: Decodable { let type: String; let push: Bool; let inApp: Bool }
        let prefs: [Pref] = try await api.get("notifications/preferences")
        return prefs.compactMap { p in ActivityType(rawValue: p.type).map { NotificationPreference(type: $0, push: p.push, inApp: p.inApp) } }
    }

    func setNotificationPreference(_ p: NotificationPreference) async throws {
        struct Item: Encodable { let type: String; let push: Bool; let inApp: Bool }
        struct Body: Encodable { let preferences: [Item] }
        struct Pref: Decodable { let type: String }
        let _: [Pref] = try await api.patch("notifications/preferences", body: Body(preferences: [Item(type: p.type.rawValue, push: p.push, inApp: p.inApp)]))
    }
}
