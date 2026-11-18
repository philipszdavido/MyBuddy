//
//  PhotosCheck.swift
//  MyBuddy
//
//  Keeps contact profile-photo URLs fresh. Uses `UserRepository` (no Firebase),
//  a single cancellable refresh loop, and a 10-minute cadence instead of 60 s.
//

import Foundation
import CoreData

@MainActor
class ContactListViewModel: ObservableObject {

    private static let refreshInterval: UInt64 = 10 * 60 * 1_000_000_000

    private let userRepository: UserRepository
    private var context: NSManagedObjectContext
    private var watcher: Task<Void, Never>?

    @Published var contacts: [Contact] = []

    init(context: NSManagedObjectContext, userRepository: UserRepository) {
        self.context = context
        self.userRepository = userRepository
    }

    func startPhotoWatcher() {
        guard watcher == nil else { return }   // tab re-appearing must not spawn a second loop
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkForPhotoUpdates()
                try? await Task.sleep(nanoseconds: Self.refreshInterval)
            }
        }
    }

    func stopPhotoWatcher() {
        watcher?.cancel()
        watcher = nil
    }

    func checkForPhotoUpdates() async {
        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
        do {
            let localContacts = try context.fetch(request)
            let byPhone = Dictionary(localContacts.map { ($0.phoneNumber, $0) }, uniquingKeysWith: { first, _ in first })
            let accounts = try await userRepository.accounts(matchingPhoneNumbers: Array(byPhone.keys))

            var hasChanges = false
            for account in accounts {
                guard let contact = byPhone[account.phoneNumber] else { continue }
                if contact.photo == nil {
                    contact.photo = Media(context: context)
                    hasChanges = true
                }
                if contact.photo?.url != account.photoURL {
                    contact.photo?.url = account.photoURL
                    hasChanges = true
                }
            }
            if hasChanges { try context.save() }
            contacts = localContacts
        } catch {
            let appError = AppError.wrap(error)
            if case .cancelled = appError { return }
            Log.app.error("photo refresh failed: \(appError.diagnostic, privacy: .public)")
        }
    }
}
