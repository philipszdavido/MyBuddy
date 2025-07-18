//
//  AuthViewModel.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 12/07/2025.
//

import FirebaseAuth
import SwiftUI
import Firebase
import FirebaseFirestore
import Foundation
import Contacts

struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String?
    var email: String
    var displayName: String
    var phoneNumber: Int
    var createdAt: Date = Date()
}

class AuthViewModel: ObservableObject {
    static let shared = AuthViewModel()

    @Published var user: User?
    @Published var userProfile: UserProfile?

    private var db = Firestore.firestore()
    private var listener: AuthStateDidChangeListenerHandle?
    private var contactManager = ContactManager()
    private var coreDataUtils = CoreDataUtils()
    
    @Published var isLoading = true

    init() {
        listener = Auth.auth().addStateDidChangeListener { _, user in
            self.user = user
            if let user = user {
                self.isLoading = false
                self.fetchUserProfile(user.uid, completion: { _ in })
            }
        }
        
        contactManager.requestAccessToContactStore()
    }

    deinit {
        if let listener = listener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    func register(email: String, password: String, phoneNumber: Int, displayName: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                completion(error)
                return
            }

            guard let user = result?.user else {
                completion(NSError(domain: "UserError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not created"]))
                return
            }

            let profile = UserProfile(
                id: user.uid,
                email: email,
                displayName: displayName,
                phoneNumber: phoneNumber
            )

            print("UserProfile created:", profile)

            self.coreDataUtils.clearCoreData(entityName: "Contact")
            self.coreDataUtils.clearCoreData(entityName: "UserData")

            // Save profile immediately
            self.saveUserProfile(profile)
            self.coreDataUtils.insertUserProfile(user: profile)

            // Load local phone contacts
            let contacts = self.contactManager.loadContacts()
            print("Local contacts:", contacts)

            // Fetch users in Firestore matching contacts
            self.fetchUsersByPhoneNumbers(contacts) { userProfiles in
                print("Matched user profiles:", userProfiles)

                // Save fetched users to Core Data
                self.coreDataUtils.insertContacts(contacts: userProfiles)

                self.coreDataUtils.insertUserProfile(user: profile)

                // Now everything is done
                completion(nil)
            }
        }
    }

    func login(email: String, password: String, completion: @escaping (Error?) -> Void) {
        
        print(email, password)
        
        Auth.auth().signIn(withEmail: email, password: password) {
            result,
            error in
            
            print(email, password, error)
            
            if let error = error {
                completion(error)
                return
            }
            
            print(
                result?.user.uid,
                result?.user.email,
                result?.user.displayName,
                result?.user.phoneNumber
            )
            
            self.fetchUserProfile( result?.user.uid, completion: { profile in
                
                // Load local phone contacts
                print(
                    "Loading contacts...",
                    self.contactManager.contactsAccessPermission
                )
                
                self.coreDataUtils.clearCoreData(entityName: "Contact")
                self.coreDataUtils.clearCoreData(entityName: "UserData")

                let contacts = self.contactManager.loadContacts()
                print("Local contacts:", contacts)
                
//                if !contacts.isEmpty {
//                    return
//                }
                
                guard let profile else { return }
                self.coreDataUtils.insertUserProfile(user: profile)

                // Fetch users in Firestore matching contacts
                self.fetchUsersByPhoneNumbers(contacts) { userProfiles in
                    print("Matched user profiles:", userProfiles)
                    
                    // Save fetched users to Core Data
                    self.coreDataUtils.insertContacts(contacts: userProfiles)
                                        
                    // Now everything is done
                    completion(nil)
                }
                
            })
            
            // completion(nil)
        }
    }

    func logout() {
        try? Auth.auth().signOut()
        self.user = nil
        self.userProfile = nil
        self.coreDataUtils.clearCoreData()
    }

    private func saveUserProfile(_ profile: UserProfile) {
        guard let uid = profile.id else { return }
        try? db.collection("users").document(uid).setData(from: profile)
    }

    private func fetchUserProfile(_ uid: String?, completion: @escaping (UserProfile?) -> Void) {
        guard let uid = uid else { return }
        db.collection("users").document(uid).getDocument { doc, error in
            guard let doc = doc, doc.exists else { return }
            self.userProfile = try? doc.data(as: UserProfile.self)
            completion(self.userProfile)
        }
    }
    
    private func fetchUsersByPhoneNumbers(_ phoneNumbers: [String], completion: @escaping ([UserProfile]) -> Void) {
        // Convert strings to numbers (Int64) safely
        let numberList = phoneNumbers.compactMap { Int64($0.filter("0123456789".contains)) }

        guard !numberList.isEmpty else {
            completion([])
            return
        }

        let chunks = numberList.chunked(into: 10)
        var fetchedUsers: [UserProfile] = []
        let group = DispatchGroup()

        for chunk in chunks {
            group.enter()
            db.collection("users")
                .whereField("phoneNumber", in: chunk)
                .getDocuments { snapshot, error in
                    defer { group.leave() }
                    guard let documents = snapshot?.documents else { return }

                    let users = documents.compactMap { try? $0.data(as: UserProfile.self) }
                    print("Matched users for chunk \(chunk):", users)
                    fetchedUsers.append(contentsOf: users)
                }
        }

        group.notify(queue: .main) {
            completion(fetchedUsers)
        }
    }

}
