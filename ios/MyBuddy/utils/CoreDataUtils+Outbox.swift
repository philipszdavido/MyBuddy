//
//  CoreDataUtils+Outbox.swift
//  MyBuddy
//
//  Local outbox helpers: a Message with sent == false that the current user authored is
//  "pending synchronization" and is retried (idempotently). An image whose upload has not
//  finished is stored with an empty media url and its bytes in `mediaData`.
//

import Foundation
import CoreData

struct OutboxItem {
    let message: OutgoingMessage
    /// Present while the image still has to be uploaded.
    let pendingImageData: Data?
}

extension CoreDataUtils {

    @MainActor
    func fetchUnsentOutbox(senderId: String) -> [OutboxItem] {
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        request.predicate = NSPredicate(format: "senderId == %@ AND sent == NO AND deliveryState != %ld", senderId, Int(DeliveryState.failed.rawValue))
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        request.fetchLimit = 200
        let rows = (try? managedObjectContext.fetch(request)) ?? []
        return rows.compactMap { row in
            guard let id = row.id, let chatId = row.chatId,
                  let sender = row.senderId, let recipient = row.recipientId else { return nil }
            let type = row.media?.type ?? "text"
            let url = row.media?.url ?? ""
            let pending: Data? = (type == "image" && url.isEmpty) ? row.media?.mediaData : nil
            if type == "image" && url.isEmpty && pending == nil { return nil }   // unrecoverable row
            return OutboxItem(
                message: OutgoingMessage(
                    id: id, conversationID: chatId, senderID: sender, recipientID: recipient,
                    content: row.content ?? "", type: type, mediaURL: url,
                    senderPhoneNumber: row.senderPhoneNumber, recipientPhoneNumber: row.recipientPhoneNumber
                ),
                pendingImageData: pending
            )
        }
    }

    func setMessageMediaURL(id: String, url: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let request: NSFetchRequest<Message> = Message.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            do {
                if let row = try self.managedObjectContext.fetch(request).first, let media = row.media {
                    media.url = url
                    try self.managedObjectContext.save()
                }
            } catch {
                Log.chat.error("setMessageMediaURL failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func markMessageSent(id: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let request: NSFetchRequest<Message> = Message.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            do {
                if let row = try self.managedObjectContext.fetch(request).first, row.sent == false {
                    row.sent = true
                    row.deliveryState = DeliveryState.sent.rawValue
                    try self.managedObjectContext.save()
                }
            } catch {
                Log.chat.error("markMessageSent failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The backend permanently rejected this message; stop retrying until the user asks.
    func markMessageFailed(id: String) { updateDeliveryState(id: id, to: .failed) }

    /// User tapped "Retry".
    func resetMessageToSending(id: String) { updateDeliveryState(id: id, to: .sending) }

    func deleteLocalMessage(id: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let request: NSFetchRequest<Message> = Message.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND sent == NO", id)   // never delete server-acknowledged history
            request.fetchLimit = 1
            do {
                if let row = try self.managedObjectContext.fetch(request).first {
                    if let media = row.media { self.managedObjectContext.delete(media) }
                    self.managedObjectContext.delete(row)
                    try self.managedObjectContext.save()
                }
            } catch {
                Log.chat.error("deleteLocalMessage failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func updateDeliveryState(id: String, to state: DeliveryState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let request: NSFetchRequest<Message> = Message.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND sent == NO", id)
            request.fetchLimit = 1
            do {
                if let row = try self.managedObjectContext.fetch(request).first {
                    row.deliveryState = state.rawValue
                    try self.managedObjectContext.save()
                }
            } catch {
                Log.chat.error("updateDeliveryState failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
