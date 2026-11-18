//
//  ContactManager.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 13/07/2025.
//

import Foundation
import Contacts

class ContactManager: ObservableObject {
    
    @Published var matchedUsers: [Contact] = []
    @Published var contactsAccessPermission = false
    
    func fetchContactsAndMatch(with allUsers: [Contact]) {
        let store = CNContactStore()
        var contactPhones: [String] = []

        let keys = [CNContactPhoneNumbersKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)

        do {
            try store.enumerateContacts(with: request) { (contact, _) in
                for phone in contact.phoneNumbers {
                    let cleanNumber = phone.value.stringValue.filter("0123456789".contains)
                    contactPhones.append(cleanNumber)
                }
            }

            // Normalize numbers & match with users
//            self.matchedUsers = allUsers.filter { user in
//                contactPhones.contains(user.phoneNumber.filter("0123456789".contains))
//            }

        } catch {
            debugLog("Failed to fetch contacts:", error)
        }
    }
    
    func loadContacts() -> [String] {
        
        let store = CNContactStore()
        var contactPhones: [String] = []
        
        let keys = [CNContactPhoneNumbersKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        
        do {
            
            try store.enumerateContacts(with: request) { (contact, _) in
                for phone in contact.phoneNumbers {
                    let cleanNumber = phone.value.stringValue.filter("0123456789".contains)
                    contactPhones.append(cleanNumber)
                }
            }
            
        } catch {
            debugLog("Failed to fetch contacts:", error)
        }
        
        return contactPhones
        
    }
    
    func requestAccessToContactStore() {
                
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, error in
            if granted {
                self.contactsAccessPermission = true
            } else {
                debugLog("Permission denied: \(error?.localizedDescription ?? "unknown error")")
            }
        }
        
    }

}
