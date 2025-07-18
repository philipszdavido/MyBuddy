//
//  ChatRoomViewModel.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 12/07/2025.
//

import FirebaseFirestore

class ChatRoomViewModel: ObservableObject {

    private var db = Firestore.firestore()
    private let coreDataUtils = CoreDataUtils.shared

    init() {}
    
    func sendMessage(
        chatId: String,
        currentUserId: String,
        recipientUserId: String,
        messageText: String,
        recipientUserPhoneNumber: Int64,
        currentUserPhoneNumber: Int64
    ) {

        let chatRef = db.collection("chats").document(chatId)
        
        let messageContent = messageText

        chatRef.getDocument { snapshot, error in
            
            let timestamp = Timestamp()
            
            print(recipientUserPhoneNumber, currentUserPhoneNumber)
            
            if snapshot?.exists == false {
                
                // Chat doesn't exist – create it
                chatRef.setData([
                    "participants": [currentUserId, recipientUserId],
                    "lastMessage": messageContent,
                    "lastSenderId": currentUserId,
                    "lastTimestamp": timestamp,
                    "updatedAt": timestamp,
                    "recipientUserPhoneNumber": recipientUserPhoneNumber,
                    "currentUserPhoneNumber": currentUserPhoneNumber,
                    "lastSenderPhoneNumber": currentUserPhoneNumber
                ])
                
                self.coreDataUtils.insertChatMsg(
                    id: chatId,
                    currentUserId: currentUserId,
                    recipientUserId: recipientUserId,
                    lastMessage: messageContent,
                    lastSenderId: currentUserId,
                    lastTimestamp: timestamp.dateValue(),
                    updatedAt: timestamp.dateValue(),
                    recipientUserPhoneNumber: recipientUserPhoneNumber,
                    currentUserPhoneNumber: currentUserPhoneNumber,
                    lastSenderPhoneNumber: currentUserPhoneNumber
                )
                
            } else {
                
                // Chat exists – update lastMessage
                chatRef.updateData([
                    "lastMessage": messageContent,
                    "lastSenderId": currentUserId,
                    "lastTimestamp": timestamp,
                    "updatedAt": timestamp,
                    "recipientUserPhoneNumber": recipientUserPhoneNumber,
                    "currentUserPhoneNumber": currentUserPhoneNumber,
                    "lastSenderPhoneNumber": currentUserPhoneNumber
                ])
                
                self.coreDataUtils.insertChatMsg(
                    id: chatId,
                    currentUserId: currentUserId,
                    recipientUserId: recipientUserId,
                    lastMessage: messageContent,
                    lastSenderId: currentUserId,
                    lastTimestamp: timestamp.dateValue(),
                    updatedAt: timestamp.dateValue(),
                    recipientUserPhoneNumber: recipientUserPhoneNumber,
                    currentUserPhoneNumber: currentUserPhoneNumber,
                    lastSenderPhoneNumber: currentUserPhoneNumber
                )
                
            }

            // Then add the message
            let messageRef = chatRef.collection("messages").document()
            messageRef.setData([
                "senderId": currentUserId,
                "recipientId": recipientUserId,
                "content": messageContent,
                "timestamp": timestamp,
                "seen": false
            ])
            
            self.coreDataUtils.insertMessage(
                id: messageRef.documentID,
                senderId: currentUserId,
                recipientId: recipientUserId,
                content: messageContent,
                timestamp: timestamp.dateValue(),
                seen: false
            )
            
        }

    }

    

}
