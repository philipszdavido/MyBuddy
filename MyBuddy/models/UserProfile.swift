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
