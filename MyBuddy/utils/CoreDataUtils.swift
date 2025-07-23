//
//  CoreDataUtils.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 14/07/2025.
//

import Foundation
import CoreData
import FirebaseCore


class CoreDataUtils {
    
    let managedObjectContext = PersistenceController.shared.container.viewContext
    static let shared = CoreDataUtils()
    let entities = ["Contact", "UserData", "Message", "Media", "ChatMsg", "Feed"]

    func loadChatMsgs() -> [ChatMsg] {
        
        var chats: [ChatMsg] = []
        
        let fetchRequest: NSFetchRequest<ChatMsg> = ChatMsg.fetchRequest()

        do {
            
            chats = try managedObjectContext.fetch(fetchRequest)
                        
        } catch {
            print(error)
        }
        
        return chats

    }
    
    func loadContacts() -> [Contact] {
        
        var contacts: [Contact] = []
        
        let fetchRequest: NSFetchRequest<Contact> = Contact.fetchRequest()

        do {
            
            contacts = try managedObjectContext.fetch(fetchRequest)
                        
        } catch {
            print(error)
        }
        
        return contacts

    }
    
    func loadMessages() -> [Message] {
        
        var contacts: [Message] = []
        
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()

        do {
            
            contacts = try managedObjectContext.fetch(fetchRequest)
                        
        } catch {
            print(error)
        }
        
        return contacts

    }
    
    func fetchUserData() -> UserData? {
        
        let fetchRequest: NSFetchRequest = UserData.fetchRequest()
        
        var results: UserData? = nil
        
        do {
            
            let data = try managedObjectContext.fetch(fetchRequest)
            results = data.first
            
        } catch {
            
        }
        
        return results
    }
    
    func getContactWithNumber(phoneNumber: Int64) -> Contact? {
        
        var contact: Contact? = nil;
        
        let fetchRequest: NSFetchRequest<Contact> = Contact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "phoneNumber == %@", NSNumber(value: phoneNumber))
        
        do {
            
            let results = try managedObjectContext.fetch(fetchRequest)
            
            if !results.isEmpty {
                
                contact = results.first
                
            } else {
                
                let userFetchRequest = UserData.fetchRequest()
                userFetchRequest.predicate = NSPredicate(
                    format: "phoneNumber == %@",
                    NSNumber(value: phoneNumber)
                )
                
                let userResults = try managedObjectContext.fetch(
                    userFetchRequest
                )
                
//                if !userResults.isEmpty {
//                    
//                    contact = Contact(context: managedObjectContext)
//                    
//                    if let user = userResults.first {
//                        contact?.displayName = user.displayName
//                        contact?.phoneNumber = user.phoneNumber
//                        contact?.id = user.id
//                    }
//                    
//                }
                
            }
            
        } catch {
            
        }
        
        return contact

    }
    
    func insertContacts(contacts: [UserProfile]) {
        for user in contacts {
            let fetchRequest: NSFetchRequest<Contact> = Contact.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", user.id ?? "")

            do {
                let existing = try managedObjectContext.fetch(fetchRequest)
                if existing.isEmpty {
                    let userContact = Contact(context: managedObjectContext)
                    userContact.id = user.id
                    userContact.displayName = user.displayName
                    userContact.phoneNumber = Int64(user.phoneNumber)
                }
            } catch {
                print("Fetch error: \(error)")
            }
        }

        do {
            try managedObjectContext.save()
        } catch {
            print("Failed to save contacts: \(error)")
        }
    }
    
    func deleteContact(object: NSManagedObject) {
        managedObjectContext.delete(object)
    }

    func insertUserProfile(user: UserProfile) {
        
        let fetchRequest: NSFetchRequest<UserData> = UserData.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", user.id ?? "")

        do {
            
            let existing = try managedObjectContext.fetch(fetchRequest)
            
            if existing.isEmpty {
                
                let userData = UserData(context: managedObjectContext)
                userData.id = user.id
                userData.displayName = user.displayName
                userData.phoneNumber = Int64(user.phoneNumber)
                userData.email = user.email
                userData.createdAt = user.createdAt

                try managedObjectContext.save()
                
            }
            
        } catch {
            print("Failed to add user profile: \(error)")
        }
    }
    
    func insertChatMsg(
        id: String,
        currentUserId: String,
        recipientUserId: String,
        lastMessage: String,
        lastSenderId: String,
        lastTimestamp: Date,
        updatedAt: Date,
        recipientUserPhoneNumber: Int64,
        currentUserPhoneNumber: Int64,
        lastSenderPhoneNumber: Int64,
        type: String
    ) {
        
        let fetchRequest: NSFetchRequest<ChatMsg> = ChatMsg.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)

        do {
            
            let existing = try managedObjectContext.fetch(fetchRequest)
            var chatMsg: ChatMsg
            
            if existing.isEmpty {
                
                chatMsg = ChatMsg(context: managedObjectContext)
                                
            } else {
                
                chatMsg = existing[0]

            }
            
            chatMsg.id = id
            chatMsg.currentUserId = currentUserId
            chatMsg.lastMessage = lastMessage
            chatMsg.lastSenderId = lastSenderId
            chatMsg.lastTimestamp = lastTimestamp
            chatMsg.recipientUserId = recipientUserId
            chatMsg.updatedAt = updatedAt
            chatMsg.recipientUserPhoneNumber = recipientUserPhoneNumber
            chatMsg.currentUserPhoneNumber = currentUserPhoneNumber
            chatMsg.lastSenderPhoneNumber = lastSenderPhoneNumber
            chatMsg.type = type

            try managedObjectContext.save()

            
        } catch {
            print("Error inserting chat into Core Data.")
        }

    }
    
    func removeChatMsg(id: String) {
        
        let fetchRequest: NSFetchRequest<ChatMsg> = ChatMsg.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)
        
        do {
            
            let existing = try managedObjectContext.fetch(fetchRequest)
            
            if !existing.isEmpty {
                managedObjectContext.delete(existing[0])
            }
            
        } catch {
            
        }

    }
    
    func _insertMessage(
        id: String,
        senderId: String,
        recipientId: String,
        content: String,
        timestamp: Date,
        type: String,
        mediaUrl: String?,
        mediaData: Data?,
        seen: Bool
    ) {
        
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)

        do {
            
            let existing = try managedObjectContext.fetch(fetchRequest)
            
            var message: Message
            
            if existing.isEmpty {
                
                message = Message(context: managedObjectContext)
                
                if let mediaUrl {
                    
                    let media = Media(context: managedObjectContext)
                    media.id = id
                    media.type = type
                    media.url = mediaUrl
                    
                    if let mediaData {

                        media.mediaData = mediaData

                    }
                                    
                    message.media = media

                }

                                
            } else {
                
                message = existing[0]
                
                let media = message.media ?? Media(
                    context: managedObjectContext
                )
                                
                if let mediaUrl {
                    
                    media.id = id
                    media.type = type
                    media.url = mediaUrl
                    
                    if let mediaData {

                        media.mediaData = mediaData

                    }
                                    
                    message.media = media

                }


            }
            
            message.id = id
            message.senderId = senderId
            message.recipientId = recipientId
            message.content = content
            message.seen = seen
            message.timestamp = timestamp
            
            try managedObjectContext.save()
            
        } catch {
            
            print("Error inserting message into Core Data.")
            
        }
    }
    
    func insertMessage(
        id: String,
        senderId: String,
        recipientId: String,
        content: String,
        timestamp: Date,
        type: String,
        mediaUrl: String?,
        mediaData: Data?,
        recipientPhoneNumber: Int64?,
        senderPhoneNumber: Int64?,
        seen: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)

            do {
                let existing = try self.managedObjectContext.fetch(fetchRequest)
                let message: Message

                if existing.isEmpty {
                    message = Message(context: self.managedObjectContext)
                } else {
                    message = existing[0]
                }

                // Set/update message fields
                message.id = id
                message.senderId = senderId
                message.recipientId = recipientId
                message.content = content
                message.timestamp = timestamp
                
                if let recipientPhoneNumber {
                    message.recipientPhoneNumber = recipientPhoneNumber
                }
                
                if let senderPhoneNumber {
                    message.senderPhoneNumber = senderPhoneNumber
                }
                
                message.seen = seen

                // Handle media
                if let mediaUrl {
                    let media = message.media ?? Media(context: self.managedObjectContext)
                    media.id = id
                    media.type = type
                    media.url = mediaUrl

                    if let mediaData {
                        media.mediaData = mediaData
                    }

                    message.media = media
                }

                try self.managedObjectContext.save()
                print("✅ Message inserted/updated successfully.")

            } catch {
                print("❌ Error inserting/updating message: \(error.localizedDescription)")
            }
        }
    }
    
    func loadChatMessages(chatId: String) -> [Message] {
        
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", chatId)
        
        var messages: [Message] = []
        
        do {
            messages = try managedObjectContext.fetch(fetchRequest)
        } catch {
            
        }
        
        return messages

    }

    func removeMessage(id: String) {
        
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)
        
        do {
            
            let existing = try managedObjectContext.fetch(fetchRequest)
            
            if !existing.isEmpty {
                managedObjectContext.delete(existing[0])
            }
            
        } catch {
            
        }

    }
    
    func fetchMediaWithID(id: String) -> Media? {
        
        var media: Media? = nil
        
        let fetchRequest: NSFetchRequest<Media> = Media.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)
        
        do {
            
            let mediaFound = try managedObjectContext.fetch(fetchRequest)
            
            if !mediaFound.isEmpty {
                media = mediaFound[0]
            }
                        
        } catch {
            print("Error fetching media ", id)
        }
        
        return media
        
    }
    
    func insertFeed(
        id: String,
        timestamp: Date?,
        feedOwnerId: Int64?,
        content: String?,
        likes: Int64?,
        dislikes: Int64?
    ) {
        
        let fetchRequest: NSFetchRequest<Feed> = Feed.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)

        print("insertfeed", feedOwnerId)

        do {
            let existing = try self.managedObjectContext.fetch(fetchRequest)
            let feed: Feed
            
            if existing.isEmpty {
                feed = Feed(context: self.managedObjectContext)
            } else {
                feed = existing[0]
            }
            
            feed.id = id
            
            if let content {
                feed.content = content
            }
            
            if let dislikes {
                feed.dislikes = dislikes
            }
            
            if let likes {
                feed.likes = likes
            }
            
            if let timestamp {
                feed.timestamp = timestamp
            }
            
            if let feedOwnerId {
                
                let contact = getContactWithNumber(phoneNumber: feedOwnerId)
                print("insertfeed", contact, feed)
                if feed.contact == nil {
                    feed.contact = contact
                }
                
            }
            
            try managedObjectContext.save()
            
        } catch {
            
        }
    }
    
    func clearCoreData() {

        for entityName in entities {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

            do {
                try managedObjectContext.execute(batchDeleteRequest)
                try managedObjectContext.save()
                print("\(entityName) cleared.")
            } catch {
                print("Failed to clear \(entityName): \(error)")
            }
        }
    }
    
    func clearCoreData(entityName: String) {


        deleteAllManually(entityName: entityName)
        
    }
    
    func deleteAllManually(entityName: String) {

        let context: NSManagedObjectContext = managedObjectContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)

        do {
            let results = try context.fetch(fetchRequest)
            for object in results as! [NSManagedObject] {
                context.delete(object)
            }
            try context.save()
            print("All \(entityName) objects deleted.")
        } catch {
            print("Error deleting \(entityName): \(error)")
        }
    }

}
