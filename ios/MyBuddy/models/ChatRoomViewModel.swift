//
//  ChatRoomViewModel.swift
//  MyBuddy
//
//  Writes outgoing messages to the local store (optimistic, sent == false) and asks the outbox to
//  deliver them. Uploading and sending happen in `OutboxRetrier`, so first sends and retries share
//  one idempotent code path. No Firebase types here.
//

import UIKit

class ChatRoomViewModel: ObservableObject {

    private let coreDataUtils = CoreDataUtils.shared

    static let shared = ChatRoomViewModel()

    init() {}

    func sendMessage(
        chatId: String,
        currentUserId: String,
        recipientUserId: String,
        messageText: String,
        recipientUserPhoneNumber: Int64,
        currentUserPhoneNumber: Int64,
        mediaType: FileType = .text,
        mediaUrl: String? = nil,
        mediaData: Data? = nil
    ) {
        // Client-generated id => retries are idempotent.
        let messageId = UUID().uuidString
        let now = Date()

        coreDataUtils.insertChatMsg(
            id: chatId,
            currentUserId: currentUserId,
            recipientUserId: recipientUserId,
            lastMessage: messageText,
            lastSenderId: currentUserId,
            lastTimestamp: now,
            updatedAt: now,
            recipientUserPhoneNumber: recipientUserPhoneNumber,
            currentUserPhoneNumber: currentUserPhoneNumber,
            lastSenderPhoneNumber: currentUserPhoneNumber,
            type: mediaType.rawValue
        )
        // Optimistic local write: shows immediately as "sending" (sent == false).
        // An empty (non-nil) mediaUrl creates the Media row for an image that is still to be uploaded.
        coreDataUtils.insertMessage(
            id: messageId,
            chatId: chatId,
            senderId: currentUserId,
            recipientId: recipientUserId,
            content: messageText,
            timestamp: now,
            type: mediaType.rawValue,
            mediaUrl: mediaUrl,
            mediaData: mediaData,
            recipientPhoneNumber: recipientUserPhoneNumber,
            senderPhoneNumber: currentUserPhoneNumber,
            seen: false,
            sent: false
        )

        OutboxRetrier.requestFlush()
    }

    /// Resizes and compresses off the main thread, stores the message locally, then the outbox uploads and sends.
    func sendImage(
        _ image: UIImage,
        caption: String,
        chatId: String,
        currentUserId: String,
        recipientUserId: String,
        recipientUserPhoneNumber: Int64,
        currentUserPhoneNumber: Int64
    ) {
        Task {
            guard let processed = await ImageProcessor.prepare(image, maxDimension: ImageProcessor.chatMaxDimension) else {
                Log.chat.error("image could not be prepared for sending")
                return
            }
            sendMessage(
                chatId: chatId,
                currentUserId: currentUserId,
                recipientUserId: recipientUserId,
                messageText: caption,
                recipientUserPhoneNumber: recipientUserPhoneNumber,
                currentUserPhoneNumber: currentUserPhoneNumber,
                mediaType: .image,
                mediaUrl: "",
                mediaData: processed.data
            )
        }
    }

    /// User tapped Retry on a failed message.
    func retry(messageID: String) {
        coreDataUtils.resetMessageToSending(id: messageID)
        OutboxRetrier.requestFlush()
    }

    /// Removes an unsent message the user no longer wants to send.
    func discard(messageID: String) {
        coreDataUtils.deleteLocalMessage(id: messageID)
    }
}
