//
//  UserProfile.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 24/07/2025.
//

import Foundation
import FirebaseFirestore

struct UserMedia: Codable, Identifiable  {
    var id: String
    var type: String
    var url: String
    var mediaData: Data
}

struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String?
    var email: String
    var displayName: String
    var phoneNumber: Int64
    var createdAt: Date = Date()
    
    var media: UserMedia
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName
        case phoneNumber
        case createdAt
        case media
    }

    init(
        id: String? = nil,
        email: String,
        displayName: String,
        phoneNumber: Int64,
        createdAt: Date = .now
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.phoneNumber = phoneNumber
        self.createdAt = createdAt
        self.media = UserMedia(
            id: "",
            type: "",
            url: "",
            mediaData: Data()
        )
    }
    
    init(
        id: String? = nil,
        email: String,
        displayName: String,
        phoneNumber: Int64,
        createdAt: Date = .now,
        media: UserMedia
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.phoneNumber = phoneNumber
        self.createdAt = createdAt
        self.media = media
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self._id = try container.decode(DocumentID<String>.self, forKey: .id)
        self.email = try container.decode(String.self, forKey: .email)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.phoneNumber = try container.decode(Int64.self, forKey: .phoneNumber)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        
        self.media = try container.decodeIfPresent(UserMedia.self, forKey: .media) ?? UserMedia(
            id: "", type: "", url: "", mediaData: Data()
        )
    }
    
    init(from contact: Contact) {
        
        self.email = ""
        self.id = contact.id
        
        var media = UserMedia(
            id: "",
            type: "",
            url: "",
            mediaData: Data()
        )
                
        self.displayName = contact.displayName ?? String(contact.phoneNumber)
        
        if let photo = contact.photo {
            
            if let id = photo.id {
                media.id = id
            }
            
            if let mediaData = photo.mediaData {
                media.mediaData = mediaData
            }
            
            if let type = photo.type {
                media.type = type
            }
            
            if let url = photo.url {
                media.url = url
            }
            
        }
        
        self.media = media
        self.phoneNumber = contact.phoneNumber
        
    }
    
}
