//
//  ChatDetails.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 19/07/2025.
//

import Foundation

enum FileType: String {
    case text
    case image
    case video
    case gif
}

let imageExtensions = ["jpg", "jpeg", "png", "heic"]
let videoExtensions = ["mp4", "mov", "m4v"]

class ChatDetails: ObservableObject {
    @Published var chatId: String
    @Published var currentUserId: String
    @Published var recipientUserId: String
    @Published var messageText: String
    @Published var recipientUserPhoneNumber: Int64
    @Published var currentUserPhoneNumber: Int64
    @Published var mediaUrl: String? = nil
    @Published var data: Data? = nil
    
    // Computed property – non-static and uses instance mediaUrl
    var fileType: FileType {
        guard let mediaUrl = mediaUrl else { return .text }
        let ext = mediaUrl.split(separator: ".").last?.lowercased() ?? ""
        
        if videoExtensions.contains(ext) {
            return .video
        }
        
        if imageExtensions.contains(ext) {
            return .image
        }
        
        if ext == "gif" {
            return .gif
        }
        
        return .text
    }
    
    init(chatId: String,
         currentUserId: String,
         recipientUserId: String,
         messageText: String,
         recipientUserPhoneNumber: Int64,
         currentUserPhoneNumber: Int64,
         mediaUrl: String? = nil,
         data: Data? = nil) {
        
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.recipientUserId = recipientUserId
        self.messageText = messageText
        self.recipientUserPhoneNumber = recipientUserPhoneNumber
        self.currentUserPhoneNumber = currentUserPhoneNumber
        self.mediaUrl = mediaUrl
        self.data = data
    }
}
