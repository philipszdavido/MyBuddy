//
//  FirebaseMessage.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 01/08/2025.
//

import Foundation
import FirebaseCore

enum MessageType: String {
    case text, image, video, location, contact, document, poll, event, unknown

    init(type: String) {
        self = MessageType(rawValue: type.lowercased()) ?? .unknown
    }
}

struct FirebaseMessage {
    
    let id: String
    var senderId: String
    var recipientId: String
    var content: String
    
    var timestamp: Date
    var seen: Bool
    var sent: Bool
    var type: String
    
    var mediaUrl: String
    
    var recipientPhoneNumber: Int64
    var senderPhoneNumber: Int64
    var chatId: String
    
    var mediaData: Data?
    var messageType: MessageType
    
    init(from data: [String : Any], id: String) {
        
        self.id = id;
        self.senderId = data["senderId"] as? String ?? ""
        self.recipientId = data["recipientId"] as? String ?? ""
        self.content = data["content"] as? String ?? ""
        
        self.timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
        
        self.seen = data["seen"] as? Bool ?? true
        self.sent = data["sent"] as? Bool ?? true
        
        self.type = data["type"] as? String ?? ""
        
        self.mediaUrl = data["mediaUrl"] as? String ?? ""
        
        self.recipientPhoneNumber = data["recipientPhoneNumber"] as? Int64 ?? 0
        self.senderPhoneNumber = data["senderPhoneNumber"] as? Int64 ?? 0
        
        self.chatId = data["chatId"] as? String ?? ""
        self.messageType = MessageType(type: self.type)

    }
    
}
