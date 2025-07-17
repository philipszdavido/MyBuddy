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
            print("Failed to fetch contacts:", error)
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
            print("Failed to fetch contacts:", error)
        }
        
        return contactPhones
        
    }
    
    func addMockContacts(to store: CNContactStore) {
        let saveRequest = CNSaveRequest()
        
        let contact1 = CNMutableContact()
        contact1.givenName = "Alice"
        contact1.familyName = "Smith"
        contact1.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile,
                                                value: CNPhoneNumber(stringValue: "1234567890"))]

        let contact2 = CNMutableContact()
        contact2.givenName = "Bob"
        contact2.familyName = "Johnson"
        contact2.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile,
                                                value: CNPhoneNumber(stringValue: "9876543210"))]

        saveRequest.add(contact1, toContainerWithIdentifier: nil)
        saveRequest.add(contact2, toContainerWithIdentifier: nil)

        do {
            try store.execute(saveRequest)
            print("Mock contacts added.")
        } catch {
            print("Failed to add contacts: \(error)")
        }
    }
    
    func requestAccessToContactStore() {
                
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, error in
            if granted {
                self.contactsAccessPermission = true
            } else {
                print("Permission denied: \(error?.localizedDescription ?? "unknown error")")
            }
        }
        
    }

}
