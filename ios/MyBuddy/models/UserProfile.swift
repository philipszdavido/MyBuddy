//
//  UserProfile.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 24/07/2025.
//

import Foundation
import FirebaseFirestore

struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String?
    var email: String
    var displayName: String
    var phoneNumber: Int64
    var url: String?
    var createdAt: Date = Date()
}

extension UserProfile {
    /// Bridge from the backend-independent domain type to the legacy Core Data insert API.
    init(account: UserAccount) {
        self.init(id: account.id, email: account.email, displayName: account.displayName,
                  phoneNumber: account.phoneNumber, url: account.photoURL, createdAt: account.createdAt)
    }
}
