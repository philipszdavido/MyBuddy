//
//  ConversationViewModel.swift
//  MyBuddy
//
//  State of one open conversation on the MyBuddy API backend. The server is the source of truth: the
//  view model loads the newest page, merges realtime events by client id, and after every reconnect
//  catches up with `afterSeq`. Outgoing messages appear immediately (pending), are retried, and
//  unsent text survives an app restart (PendingMessageStore).
//

import Foundation
import UIKit

/// One row in the transcript: a server message, or a local message still being sent.
struct TranscriptItem: Identifiable, Equatable {
    enum State: Equatable { case sent, sending, failed }
    var message: ChatItem
    var state: State
    var localImage: UIImage?
    var uploadProgress: Double?

    var id: String { message.clientID }

    static func == (a: TranscriptItem, b: TranscriptItem) -> Bool {
        a.message == b.message && a.state == b.state && a.uploadProgress == b.uploadProgress && (a.localImage == nil) == (b.localImage == nil)
    }
}

@MainActor
final class ConversationViewModel: ObservableObject {
    @Published private(set) var conversation: ChatConversation?
    @Published private(set) var items: [TranscriptItem] = []
    @Published private(set) var typingUsers: Set<String> = []
    @Published private(set) var hasOlder = false
    @Published private(set) var loading = true
    @Published private(set) var meID = ""
    @Published var errorMessage: String?

    let conversationID: String
    private let repository: MessagingRepository
    private let social: SocialRepository?
    private var eventsTask: Task<Void, Never>?
    private var typingTimeouts: [String: Task<Void, Never>] = [:]
    private var lastTypingSent = Date.distantPast
    private var pendingImages: [String: Data] = [:]

    init(conversationID: String, repository: MessagingRepository, social: SocialRepository?) {
        self.conversationID = conversationID
        self.repository = repository
        self.social = social
    }

    deinit { eventsTask?.cancel() }

    var isGroup: Bool { conversation?.kind == .group }
    var isRequest: Bool { conversation?.isRequest ?? false }
    var lastServerSeq: Int { items.filter { $0.state == .sent }.map(\.message.seq).max() ?? 0 }

    // MARK: Lifecycle

    func start() async {
        do {
            meID = try await repository.currentUserID()
            conversation = try await repository.conversation(id: conversationID)
            let page = try await repository.messages(conversationID: conversationID, beforeSeq: nil, afterSeq: nil)
            items = page.items.reversed().map { TranscriptItem(message: $0, state: .sent) }
            hasOlder = page.hasMore
            restorePending()
            loading = false
            await markRead()
        } catch {
            loading = false
            report(error)
        }
        listen()
        retryPending()
    }

    func stop() {
        eventsTask?.cancel()
        eventsTask = nil
        repository.typing(conversationID: conversationID, isTyping: false)
    }

    private func listen() {
        eventsTask?.cancel()
        let stream = repository.events()
        eventsTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: ChatEvent) async {
        switch event {
        case .connected:
            await catchUp()
            retryPending()
        case .message(let m) where m.conversationID == conversationID:
            if m.seq > lastServerSeq + 1 && lastServerSeq > 0 { await catchUp() }
            merge([m])
            typingUsers.remove(m.senderID)
            if m.senderID != meID { await markRead() }
        case .messageDeleted(let c, let id) where c == conversationID:
            if let i = items.firstIndex(where: { $0.message.id == id }) {
                items[i].message.deleted = true
                items[i].message.text = nil
                items[i].message.media = []
            }
        case .conversationChanged(let c) where c == conversationID:
            conversation = try? await repository.conversation(id: conversationID)
        case .read(let c, let user, let seq) where c == conversationID:
            if let i = conversation?.participants.firstIndex(where: { $0.id == user }) {
                let p = conversation!.participants[i]
                conversation?.participants[i] = ChatParticipant(user: p.user, isAdmin: p.isAdmin, lastReadSeq: max(seq, p.lastReadSeq ?? 0))
            }
        case .typing(let c, let user, let isTyping) where c == conversationID && user != meID:
            if isTyping {
                typingUsers.insert(user)
                typingTimeouts[user]?.cancel()
                typingTimeouts[user] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(6))
                    self?.typingUsers.remove(user)
                }
            } else {
                typingUsers.remove(user)
            }
        default:
            break
        }
    }

    /// Fetches everything after the newest message we have (missed while disconnected).
    private func catchUp() async {
        guard !loading else { return }
        do {
            var after = lastServerSeq
            repeat {
                let page = try await repository.messages(conversationID: conversationID, beforeSeq: nil, afterSeq: after)
                merge(page.items)
                guard page.hasMore, let newest = page.items.map(\.seq).max() else { break }
                after = newest
            } while true
            conversation = try await repository.conversation(id: conversationID)
            await markRead()
        } catch {
            Log.chat.error("catch-up failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
        }
    }

    func loadOlder() async {
        guard hasOlder, let oldest = items.first(where: { $0.state == .sent })?.message.seq else { return }
        do {
            let page = try await repository.messages(conversationID: conversationID, beforeSeq: oldest, afterSeq: nil)
            let older = page.items.reversed().filter { m in !items.contains { $0.id == m.clientID } }
            items.insert(contentsOf: older.map { TranscriptItem(message: $0, state: .sent) }, at: 0)
            hasOlder = page.hasMore
        } catch { report(error) }
    }

    /// Server messages replace pending ones with the same client id; order is by seq, pending last.
    private func merge(_ messages: [ChatItem]) {
        for m in messages {
            if let i = items.firstIndex(where: { $0.id == m.clientID }) {
                items[i] = TranscriptItem(message: m, state: .sent)
                PendingMessageStore.shared.remove(clientID: m.clientID)
                pendingImages[m.clientID] = nil
            } else {
                items.append(TranscriptItem(message: m, state: .sent))
            }
        }
        let sent = items.filter { $0.state == .sent }.sorted { $0.message.seq < $1.message.seq }
        let pending = items.filter { $0.state != .sent }
        items = sent + pending
    }

    // MARK: Sending

    func send(text: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let item = pendingItem(text: body, kind: .text)
        items.append(item)
        PendingMessageStore.shared.save(PendingMessage(clientID: item.id, conversationID: conversationID, text: body, createdAt: item.message.createdAt))
        repository.typing(conversationID: conversationID, isTyping: false)
        Task { await deliver(item.id) }
    }

    func send(image: UIImage, caption: String) {
        Task {
            guard let prepared = await ImageProcessor.prepare(image, maxDimension: ImageProcessor.chatMaxDimension) else { return }
            var item = pendingItem(text: caption.isEmpty ? nil : caption, kind: .image)
            item.localImage = UIImage(data: prepared.data)
            item.uploadProgress = 0
            pendingImages[item.id] = prepared.data
            items.append(item)
            await deliver(item.id)
        }
    }

    func retry(_ item: TranscriptItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].state = .sending
        Task { await deliver(item.id) }
    }

    func discard(_ item: TranscriptItem) {
        items.removeAll { $0.id == item.id }
        PendingMessageStore.shared.remove(clientID: item.id)
        pendingImages[item.id] = nil
    }

    func delete(_ item: TranscriptItem) async {
        do {
            try await repository.deleteMessage(id: item.message.id)
            if let i = items.firstIndex(where: { $0.id == item.id }) {
                items[i].message.deleted = true
                items[i].message.text = nil
                items[i].message.media = []
            }
        } catch { report(error) }
    }

    private func pendingItem(text: String?, kind: ChatMessageKind) -> TranscriptItem {
        let clientID = UUID().uuidString
        let me = conversation?.participants.first { $0.id == meID }?.user
        return TranscriptItem(
            message: ChatItem(id: clientID, clientID: clientID, conversationID: conversationID, seq: .max, sender: me, senderID: meID,
                              kind: kind, text: text, media: [], replyToText: nil, reactions: [:], edited: false, deleted: false, createdAt: Date()),
            state: .sending
        )
    }

    private func deliver(_ clientID: String) async {
        guard let item = items.first(where: { $0.id == clientID }) else { return }
        do {
            var mediaIDs: [String] = []
            if let data = pendingImages[clientID] {
                guard let social else { throw AppError.validation("Photos aren't supported here") }
                let media = try await social.uploadMedia(data, mimeType: "image/jpeg", purpose: .message) { [weak self] progress in
                    Task { @MainActor in
                        if let i = self?.items.firstIndex(where: { $0.id == clientID }) { self?.items[i].uploadProgress = progress }
                    }
                }
                mediaIDs = [media.id]
            }
            let sent = try await repository.send(conversationID: conversationID, clientID: clientID, text: item.message.text, mediaIDs: mediaIDs)
            merge([sent])
            if conversation?.isRequest == true { conversation?.isRequest = false }
        } catch {
            let e = AppError.wrap(error)
            if let i = items.firstIndex(where: { $0.id == clientID }) {
                items[i].state = .failed
                items[i].uploadProgress = nil
            }
            if !e.isRetryable { report(error) }
        }
    }

    private func restorePending() {
        for p in PendingMessageStore.shared.pending(conversationID: conversationID) where !items.contains(where: { $0.id == p.clientID }) {
            var item = pendingItem(text: p.text, kind: .text)
            item.message = ChatItem(id: p.clientID, clientID: p.clientID, conversationID: conversationID, seq: .max, sender: item.message.sender,
                                    senderID: meID, kind: .text, text: p.text, media: [], replyToText: nil, reactions: [:], edited: false,
                                    deleted: false, createdAt: p.createdAt)
            item.state = .failed
            items.append(item)
        }
    }

    /// Re-sends failed messages after a reconnect (sends are idempotent on the client id).
    private func retryPending() {
        for item in items where item.state == .failed && pendingImages[item.id] == nil {
            retry(item)
        }
    }

    // MARK: Read state & typing

    func markRead() async {
        guard lastServerSeq > 0 else { return }
        await repository.markRead(conversationID: conversationID, seq: lastServerSeq)
    }

    func userIsTyping(_ text: String) {
        guard !text.isEmpty, Date().timeIntervalSince(lastTypingSent) > 3 else { return }
        lastTypingSent = Date()
        repository.typing(conversationID: conversationID, isTyping: true)
    }

    /// Direct chats: the newest of my messages the other person has read.
    var seenSeq: Int? {
        guard !isGroup, let other = conversation?.others(meID).first else { return nil }
        return other.lastReadSeq
    }

    // MARK: Requests

    func acceptRequest() async {
        do {
            try await repository.accept(conversationID: conversationID)
            conversation?.isRequest = false
        } catch { report(error) }
    }

    func declineRequest() async -> Bool {
        do {
            try await repository.leave(conversationID: conversationID)
            return true
        } catch {
            report(error)
            return false
        }
    }

    func reloadConversation() async {
        conversation = try? await repository.conversation(id: conversationID)
    }

    private func report(_ error: Error) {
        let e = AppError.wrap(error)
        if case .cancelled = e { return }
        errorMessage = e.userMessage
    }
}

// MARK: - Pending messages (survive app restarts)

struct PendingMessage: Codable, Equatable {
    let clientID: String
    let conversationID: String
    let text: String
    let createdAt: Date
}

/// Unsent text messages, persisted as JSON in Application Support. Re-sent when the conversation opens;
/// the client id makes a resend of something the server already has a no-op.
final class PendingMessageStore: @unchecked Sendable {
    static let shared = PendingMessageStore()
    private let lock = NSLock()
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending-messages.json")
    }()

    private func load() -> [PendingMessage] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PendingMessage].self, from: data)) ?? []
    }

    private func write(_ list: [PendingMessage]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func pending(conversationID: String) -> [PendingMessage] { lock.withLock { load().filter { $0.conversationID == conversationID } } }
    func save(_ message: PendingMessage) { lock.withLock { write(load().filter { $0.clientID != message.clientID } + [message]) } }
    func remove(clientID: String) { lock.withLock { write(load().filter { $0.clientID != clientID }) } }
    func clear() { lock.withLock { try? FileManager.default.removeItem(at: url) } }
}
