//
//  ChatSyncService.swift
//  MyBuddy
//
//  Bridges repository streams into the Core Data cache the UI reads from.
//  Both entry points are `async` and end when the calling task is cancelled
//  (use SwiftUI's `.task`), which removes the underlying backend listener.
//

import Foundation

@MainActor
final class ChatSyncService {
    static let shared = ChatSyncService(repository: AppContainer.shared.chatRepository)

    static let conversationLimit = 100
    static let messageWindow = 50

    private let repository: ChatRepository
    private let coreData = CoreDataUtils.shared
    private var mediaInFlight = Set<String>()
    private var loadingOlder = Set<String>()
    private var exhausted = Set<String>()

    init(repository: ChatRepository) { self.repository = repository }

    func syncConversations(userID: String) async {
        do {
            for try await conversations in repository.observeConversations(userID: userID, limit: Self.conversationLimit) {
                for c in conversations {
                    guard let other = c.otherParticipant(than: userID) else { continue } // malformed doc
                    coreData.insertChatMsg(
                        id: c.id, currentUserId: userID, recipientUserId: other,
                        lastMessage: c.lastMessage, lastSenderId: c.lastSenderID,
                        lastTimestamp: c.updatedAt, updatedAt: c.updatedAt,
                        recipientUserPhoneNumber: c.recipientUserPhoneNumber,
                        currentUserPhoneNumber: c.currentUserPhoneNumber,
                        lastSenderPhoneNumber: c.lastSenderPhoneNumber,
                        type: c.lastType
                    )
                }
            }
        } catch {
            Log.chat.error("conversation sync ended: \(AppError.wrap(error).diagnostic, privacy: .public)")
        }
    }

    func syncMessages(chatID: String) async {
        do {
            for try await messages in repository.observeLatestMessages(conversationID: chatID, limit: Self.messageWindow) {
                for m in messages.reversed() {
                    let hasMedia = !m.mediaURL.isEmpty
                    coreData.insertMessage(
                        id: m.id, chatId: chatID, senderId: m.senderID, recipientId: m.recipientID,
                        content: m.content, timestamp: m.timestamp, type: m.type,
                        mediaUrl: hasMedia ? m.mediaURL : nil, mediaData: nil,
                        recipientPhoneNumber: m.recipientPhoneNumber, senderPhoneNumber: m.senderPhoneNumber,
                        seen: m.seen, sent: m.state == .sent
                    )
                    if hasMedia { cacheMediaIfNeeded(m) }
                }
            }
        } catch {
            Log.chat.error("message sync ended: \(AppError.wrap(error).diagnostic, privacy: .public)")
        }
    }

    /// Fetches one page of history older than the oldest cached message (cursor pagination).
    func loadOlderMessages(chatID: String) async {
        guard !exhausted.contains(chatID), loadingOlder.insert(chatID).inserted,
              let oldest = coreData.oldestMessageDate(chatId: chatID) else {
            loadingOlder.remove(chatID)
            return
        }
        defer { loadingOlder.remove(chatID) }
        do {
            let page = try await repository.loadOlderMessages(
                conversationID: chatID,
                before: MessageCursor(timestamp: oldest, id: ""),
                limit: Self.messageWindow
            )
            for m in page.messages {
                let hasMedia = !m.mediaURL.isEmpty
                coreData.insertMessage(
                    id: m.id, chatId: chatID, senderId: m.senderID, recipientId: m.recipientID,
                    content: m.content, timestamp: m.timestamp, type: m.type,
                    mediaUrl: hasMedia ? m.mediaURL : nil, mediaData: nil,
                    recipientPhoneNumber: m.recipientPhoneNumber, senderPhoneNumber: m.senderPhoneNumber,
                    seen: m.seen, sent: true
                )
                if hasMedia { cacheMediaIfNeeded(m) }
            }
            if page.nextCursor == nil { exhausted.insert(chatID) }
        } catch {
            Log.chat.error("load older failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
        }
    }

    /// Downloads an image once per message (de-duplicated across snapshot emissions) and stores a
    /// downscaled JPEG, never the original. Non-image media is not cached.
    private func cacheMediaIfNeeded(_ m: ChatMessage) {
        guard m.type == "image",
              coreData.fetchMediaWithId(id: m.id)?.mediaData == nil,
              mediaInFlight.insert(m.id).inserted else { return }
        Task { [weak self] in
            defer { self?.mediaInFlight.remove(m.id) }
            do {
                let raw = try await MediaDownloader.data(from: m.mediaURL)
                let stored = await Task.detached(priority: .utility) {
                    ImageProcessor.downsampledJPEG(from: raw, maxPixel: ImageProcessor.chatMaxDimension) ?? raw
                }.value
                self?.coreData.insertMessage(
                    id: m.id, chatId: m.conversationID, senderId: m.senderID, recipientId: m.recipientID,
                    content: m.content, timestamp: m.timestamp, type: m.type,
                    mediaUrl: m.mediaURL, mediaData: stored,
                    recipientPhoneNumber: m.recipientPhoneNumber, senderPhoneNumber: m.senderPhoneNumber,
                    seen: m.seen, sent: m.state == .sent
                )
            } catch {
                Log.chat.error("media download failed: \(AppError.wrap(error).diagnostic, privacy: .public)")
            }
        }
    }
}
