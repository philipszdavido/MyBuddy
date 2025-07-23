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

            let newContact = Contact(context: viewContext)
            newContact.id = UUID().uuidString
            newContact.displayName = "NN"
            newContact.phoneNumber = 98766554
            
            let newChatMsg = ChatMsg(context: viewContext)
            newChatMsg.id = UUID().uuidString
            newChatMsg.currentUserPhoneNumber = 09889090898
            newChatMsg.recipientUserPhoneNumber = 132445456
            newChatMsg.lastSenderPhoneNumber = 89887888

            let userData = UserData(context: viewContext)
            userData.id = UUID().uuidString
            userData.displayName = "Preview User"
            userData.email = "preview@example.com"
            userData.phoneNumber = 986765656

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
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
