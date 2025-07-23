//
//  FirestoreListener.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 14/07/2025.
//

import Foundation
import Firebase
import FirebaseFirestore

class FirestoreListener: ObservableObject {
    
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()
    static let shared = FirestoreListener()
    private let chatRoomViewModel = ChatRoomViewModel.shared
    private let coreDataUtils = CoreDataUtils.shared
        
    init() {}
    
    func listenToCollection(name: String, completion: @escaping (DocumentChangeType, QueryDocumentSnapshot) -> Void) {
        listener = db.collection(name)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let _ = self, let snapshot = snapshot else {
                    print("Error fetching snapshots: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }

                snapshot.documentChanges.forEach { change in
                    switch change.type {
                    case .added:
                        print("🔵 New document added: \(change.document.documentID)")
                        completion(change.type, change.document)
                    case .modified:
                        print("🟠 Document modified: \(change.document.documentID)")
                        completion(change.type, change.document)
                    case .removed:
                        print("🔴 Document removed: \(change.document.documentID)")
                        completion(change.type, change.document)
                    }
                }

            }
    }
    
    func listenToDoc(collectionName: String, documentId: String, completion: @escaping ([String : Any]?, Error?) -> Void) {
        
        db.collection(collectionName)
            .document(documentId)
            .addSnapshotListener { documentSnapshot, error in
                guard let document = documentSnapshot, document.exists else {
                    print("Document does not exist or failed to fetch")
                    completion(nil, error)
                    return
                }
                
                print("🟢 Document updated or fetched")
                let data = document.data()
                completion(data, nil)
                print("Data: \(data ?? [:])")
            }
    }
    
    func listenToParticipants(
        currentUserId: String
    ) {
        
        db.collection("chats")
            .whereField("participants", arrayContains: currentUserId)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener {
                snapshot,
                error in

                // Update chats in Core Data
                
                guard let snapshot = snapshot else {
                    print("Error fetching snapshots: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                snapshot.documentChanges.forEach { change in
                    
                    let data = change.document.data()
                    let chatId = change.document.documentID
                    
                    let participants = data["participants"] as? [String] ?? []
                    
                    let lastMessage = data["lastMessage"] as? String ?? ""
                    let lastSenderId = data["lastSenderId"] as? String ?? ""
                    let recipientUserId = participants[0] == currentUserId ? currentUserId : participants[1]
                    
                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                    let lastTimestamp = (data["lastTimestamp"] as? Timestamp)?.dateValue() ?? Date()
                    
                    let currentUserPhoneNumber = data["currentUserPhoneNumber"] as? Int64 ?? 0

                    let recipientUserPhoneNumber = data["recipientUserPhoneNumber"] as? Int64 ?? 0

                    let lastSenderPhoneNumber = data["lastSenderPhoneNumber"] as? Int64 ?? 0

                    let type = data["type"] as? String ?? ""
                    
                    // check if sender is in contacts
                    let contact = self.coreDataUtils
                        .getContactWithNumber(phoneNumber: lastSenderPhoneNumber)
                    
                    if contact == nil {
                        
                        // if not add to contacts
                        let unknownUser = UserProfile(
                            id: lastSenderId,
                            email: "",
                            displayName: String(lastSenderPhoneNumber),
                            phoneNumber: lastSenderPhoneNumber
                        )
                        
                        self.coreDataUtils.insertUserProfile(user: unknownUser)
                        
                    }

                    switch change.type {
                    case .added:
                        print(
                            "🔵 New document added: \(change.document.documentID)"
                        )
                        
                        self.coreDataUtils
                            .insertChatMsg(
                                id: chatId,
                                currentUserId: currentUserId,
                                recipientUserId: recipientUserId,
                                lastMessage: lastMessage,
                                lastSenderId: lastSenderId,
                                lastTimestamp: lastTimestamp,
                                updatedAt: updatedAt,
                                recipientUserPhoneNumber: recipientUserPhoneNumber,
                                currentUserPhoneNumber: currentUserPhoneNumber,
                                lastSenderPhoneNumber: lastSenderPhoneNumber,
                                type: type
                            )
                        
                        break
                    case .modified:
                        print("🟠 Document modified: \(change.document.documentID)")
                        
                        self.coreDataUtils
                            .insertChatMsg(
                                id: chatId,
                                currentUserId: currentUserId,
                                recipientUserId: recipientUserId,
                                lastMessage: lastMessage,
                                lastSenderId: lastSenderId,
                                lastTimestamp: lastTimestamp,
                                updatedAt: updatedAt,
                                recipientUserPhoneNumber: recipientUserPhoneNumber,
                                currentUserPhoneNumber: currentUserPhoneNumber,
                                lastSenderPhoneNumber: lastSenderPhoneNumber,
                                type: type
                            )
                        
                        break
                    case .removed:
                        print("🔴 Document removed: \(change.document.documentID)")
                        self.coreDataUtils.removeChatMsg(id: chatId)
                        break
                    }
                }
                
                
            }

    }
    
    func listenToMessages(chatId: String) {
        
        db.collection("chats")
          .document(chatId)
          .collection("messages")
          .order(by: "timestamp", descending: false)
          .addSnapshotListener {
 snapshot,
 error in
              
              // Append messages to Core Data and reload the chat
              
              guard let snapshot = snapshot else {
                  print("Error fetching snapshots: \(error?.localizedDescription ?? "Unknown error")")
                  return
              }

              snapshot.documentChanges.forEach { change in
                  
                  let data = change.document.data()
                  let messageId = change.document.documentID
                                                                
                  let senderId = data["senderId"] as? String ?? ""
                  let recipientId = data["recipientId"] as? String ?? ""
                  let content = data["content"] as? String ?? ""

                  let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                  
                  let seen = data["seen"] as? Bool ?? true
                  
                  let mediaType = data["type"] as? String ?? ""

                  let mediaUrl = data["mediaUrl"] as? String ?? ""
                  
                  let recipientPhoneNumber = data["recipientPhoneNumber"] as? Int64
                  let senderPhoneNumber = data["senderPhoneNumber"] as? Int64
                  
                  // if mediaUrl is not empty and mediaType is image
                  // if messageId is in core data, fetch media
                  
                  print(mediaUrl, messageId)
                  
                  DispatchQueue.main.async {
                      print("DispatchQueue.main.async", messageId, mediaUrl)
                      if !mediaUrl.isEmpty {
                          
                          let media: Media? = self.coreDataUtils.fetchMediaWithID(id: messageId)
                                                    
                          guard let media else { return }
                          
                          if media.mediaData == nil {
                          
                              // fetch media data from url
                          self.chatRoomViewModel.fetchMediaFromUrlAndCache(url: mediaUrl) { data, error in
                                                                            
                              self.coreDataUtils
                                          .insertMessage(
                                            id: messageId,
                                            senderId: senderId,
                                            recipientId: recipientId,
                                            content: content,
                                            timestamp: timestamp,
                                            type: mediaType,
                                            mediaUrl: mediaUrl,
                                            mediaData: data,
                                            recipientPhoneNumber: recipientPhoneNumber,
                                            senderPhoneNumber: senderPhoneNumber,
                                            seen: seen
                                          )
                                  }
                          }
                      }
                  }

                  switch change.type {
                  case .added:
                      print(
                       "🔵 New document added: \(change.document.documentID)"
                      )
                      
                      self.coreDataUtils
                          .insertMessage(
                            id: messageId,
                            senderId: senderId,
                            recipientId: recipientId,
                            content: content,
                            timestamp: timestamp,
                            type: mediaType,
                            mediaUrl: mediaUrl,
                            mediaData: nil,
                            recipientPhoneNumber: recipientPhoneNumber,
                            senderPhoneNumber: senderPhoneNumber,
                            seen: seen
                          )
                      
                      break
                      
                  case .modified:
                      print("🟠 Document modified: \(change.document.documentID)")
                      
                      self.coreDataUtils
                          .insertMessage(
                            id: messageId,
                            senderId: senderId,
                            recipientId: recipientId,
                            content: content,
                            timestamp: timestamp,
                            type: mediaType,
                            mediaUrl: mediaUrl,
                            mediaData: nil,
                            recipientPhoneNumber: recipientPhoneNumber,
                            senderPhoneNumber: senderPhoneNumber,
                            seen: seen
                          )
                      break

                  case .removed:
                      print("🔴 Document removed: \(change.document.documentID)")
                      self.coreDataUtils.removeMessage(id: messageId)
                      break;
                  }
              }

              
          }

    }
    
    deinit {
        listener?.remove()
    }
}
