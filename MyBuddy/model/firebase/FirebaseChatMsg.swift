//
//  FirebaseChatMsg.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 01/08/2025.
//

import Foundation
import FirebaseCore

struct FirebaseChatMsg {

    let id: String
    
    let participants: [String]
    
    let lastMessage: String
    let lastSenderId: String
    var recipientUserId: String
    
    let updatedAt : Date
    let lastTimestamp : Date
    
    let currentUserPhoneNumber: Int64

    let recipientUserPhoneNumber: Int64

    let lastSenderPhoneNumber: Int64

    let type: String
    
    let currentUserId: String
    
    
    init(from data: [String : Any], id: String, currentUserId: String) {
        
        self.id = id
        
        self.participants = data["participants"] as? [String] ?? []
        
        self.lastMessage = data["lastMessage"] as? String ?? ""
        self.lastSenderId = data["lastSenderId"] as? String ?? ""
        
        self.recipientUserId = participants[0] == currentUserId ? currentUserId : participants[1]
        
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        self.lastTimestamp = (data["lastTimestamp"] as? Timestamp)?.dateValue() ?? Date()
        
        self.currentUserPhoneNumber = data["currentUserPhoneNumber"] as? Int64 ?? 0

        self.recipientUserPhoneNumber = data["recipientUserPhoneNumber"] as? Int64 ?? 0

        self.lastSenderPhoneNumber = data["lastSenderPhoneNumber"] as? Int64 ?? 0

        self.type = data["type"] as? String ?? ""
        self.currentUserId = currentUserId

    }

}
