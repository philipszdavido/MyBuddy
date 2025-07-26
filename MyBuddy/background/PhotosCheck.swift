//
//  PhotosCheck.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 26/07/2025.
//

import Foundation
import CoreData
import FirebaseFirestore

@MainActor
class ContactListViewModel: ObservableObject {

    private var db = Firestore.firestore()
    private var context: NSManagedObjectContext
    private var isWatching = false

    @Published var contacts: [Contact] = []

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func startPhotoWatcher() {
        print("📷 Starting photo watcher...")
        isWatching = true
        Task.detached { [weak self] in
            guard let self else { return }

            while await self.isWatching {
                await self.checkForPhotoUpdates()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    func stopPhotoWatcher() {
        isWatching = false
    }

    func checkForPhotoUpdates() async {
        let request: NSFetchRequest<Contact> = Contact.fetchRequest()

        do {
            
            print("checkForPhotoUpdates")
            
            // Fetch local contacts safely on the context queue
            let localContacts: [Contact] = try await context.perform {
                try self.context.fetch(request)
            }
            
            print("checkForPhotoUpdates", localContacts)

            let contactDict = Dictionary(uniqueKeysWithValues: localContacts.map { ($0.phoneNumber, $0) })
            let allPhoneNumbers = Array(contactDict.keys)
            let chunks = allPhoneNumbers.chunked(into: 10)

            var updatedUsers: [UserProfile] = []

            print("checkForPhotoUpdates", allPhoneNumbers)

            for chunk in chunks {
                let snapshot = try await db.collection("users")
                    .whereField("phoneNumber", in: chunk)
                    .getDocuments()

                let users = snapshot.documents.compactMap { try? $0.data(as: UserProfile.self) }
                updatedUsers.append(contentsOf: users)
            }

            var hasChanges = false

            for user in updatedUsers {
                if let contact = contactDict[user.phoneNumber] {
                    if contact.photo == nil {
                        contact.photo = Media(context: context)
                        hasChanges = true
                    }

                    if contact.photo?.url != user.url {
                        contact.photo?.url = user.url
                        hasChanges = true
                    }
                }
            }

            if hasChanges {
                try context.save()
            }

            contacts = localContacts

        } catch {
            print("Failed to check for photo updates: \(error.localizedDescription)")
        }
    }
}
