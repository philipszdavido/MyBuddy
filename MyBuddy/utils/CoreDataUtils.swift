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
    let entities = ["Contact", "UserData"] // Add other entity names here

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
        updatedAt: Date
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
    
    func insertMessage(
        id: String,
        senderId: String,
        recipientId: String,
        content: String,
        timestamp: Date,
        seen: Bool
    ) {
        
        let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)

        do {
            
            let existing = try managedObjectContext.fetch(fetchRequest)
            
            var message: Message
            
            if existing.isEmpty {
                
                message = Message(context: managedObjectContext)
                                
            } else {
                
                message = existing[0]

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
