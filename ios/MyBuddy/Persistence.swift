//
//  Persistence.swift
//  test
//
//  Created by Chidume Nnamdi on 14/07/2025.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        for _ in 0..<1 {

            let media = Media(context: viewContext)
            media.id = UUID().uuidString
            media.type = "image"
            media.mediaData = Mock.generateMockImageData()
            media.url = ""

            let newContact = Contact(context: viewContext)
            newContact.id = UUID().uuidString
            newContact.displayName = "NN"
            newContact.phoneNumber = 98766554
            newContact.photo = media
            
            let newChatMsg = ChatMsg(context: viewContext)
            newChatMsg.id = UUID().uuidString
            newChatMsg.currentUserPhoneNumber = 09889090898
            newChatMsg.recipientUserPhoneNumber = 132445456
            newChatMsg.lastSenderPhoneNumber = 89887888
            newChatMsg.lastMessage = "This is a very long last chat message. It is for testing how long messages will appear."

            let newChatMsg2 = ChatMsg(context: viewContext)
            newChatMsg2.id = UUID().uuidString
            newChatMsg2.currentUserPhoneNumber = 09889090898
            newChatMsg2.recipientUserPhoneNumber = 132445456
            newChatMsg2.lastSenderPhoneNumber = 89887888
            newChatMsg2.lastMessage = "This is a very long last chat message."

            let userData = UserData(context: viewContext)
            userData.id = UUID().uuidString
            userData.displayName = "NN"
            userData.email = "preview@example.com"
            userData.phoneNumber = 98766554

            let msg = Message(context: viewContext)
            msg.id = UUID().uuidString
            msg.content = "Hello"
            
            for _ in 0..<10 {
                let msg1 = Message(context: viewContext)
                msg1.id = UUID().uuidString
                msg1.content = "Hello"
            }
            
            for _ in 0..<10 {
                
                let media = Media(context: viewContext)
                media.id = UUID().uuidString
                media.type = "image"
                media.mediaData = Mock.generateMockImageData()
                media.url = ""
            }
            
            for _ in 0..<3 {
                let feed = Feed(context: viewContext)
                feed.id = UUID().uuidString
                feed.content = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
                feed.likes = 90
                feed.dislikes = 34
            }

        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MyBuddy")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        // Lightweight migration between model versions (v1 -> v2 adds Message.deliveryState and indexes).
        for description in container.persistentStoreDescriptions {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        var firstError: NSError?
        container.loadPersistentStores { _, error in firstError = error as NSError? }

        if let firstError, !inMemory {
            // The store is a cache of server data plus a small outbox. A permanently unreadable store must not
            // become a launch crash loop, so rebuild it once. (Unsent messages in the old store are lost.)
            Log.app.fault("Core Data store failed to load (\(firstError.domain, privacy: .public) \(firstError.code)); rebuilding")
            let coordinator = container.persistentStoreCoordinator
            for description in container.persistentStoreDescriptions {
                guard let url = description.url else { continue }
                try? coordinator.destroyPersistentStore(at: url, ofType: description.type, options: nil)
            }
            var secondError: NSError?
            container.loadPersistentStores { _, error in secondError = error as NSError? }
            if let secondError {
                fatalError("Core Data store unrecoverable: \(secondError), \(secondError.userInfo)")
            }
        } else if let firstError {
            fatalError("In-memory store failed: \(firstError)")
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
