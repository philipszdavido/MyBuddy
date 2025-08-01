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
                    
                    let firebaseChatMsg = FirebaseChatMsg(
                        from: data,
                        id: chatId,
                        currentUserId: currentUserId
                    )
                    
                    switch change.type {
                    case .added:
                        print(
                            "🔵 New document added: \(change.document.documentID)"
                        )
                        
                        self.coreDataUtils
                            .insertChatMsg(data: firebaseChatMsg)
                        
                        break
                    case .modified:
                        print("🟠 Document modified: \(change.document.documentID)")
                        
                        self.coreDataUtils
                            .insertChatMsg(data: firebaseChatMsg)

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
          .addSnapshotListener { snapshot, error in
              
              // Append messages to Core Data and reload the chat
              
              guard let snapshot = snapshot else {
                  print("Error fetching snapshots: \(error?.localizedDescription ?? "Unknown error")")
                  return
              }

              snapshot.documentChanges.forEach { change in
                  
                  DispatchQueue.main.async {
                      
                      let data = change.document.data()
                      let messageId = change.document.documentID
                      var firebaseMessage = FirebaseMessage(
                        from: data,
                        id: messageId
                      )
                      
                      // if mediaUrl is not empty and mediaType is image
                      // if messageId is in core data, fetch media
                                            
                      if firebaseMessage.mediaUrl.isNotEmpty {
                          
                          let media: Media? = self.coreDataUtils.fetchMediaWithId(id: messageId)
                                                    
                          if media?.mediaData == nil {
                              
                              // fetch media data from url
                              self.chatRoomViewModel.fetchMediaFromUrlAndCache(url: firebaseMessage.mediaUrl) { data, error in

                                  firebaseMessage.mediaData = data

                                  self.coreDataUtils
                                      .insertMessage(data: firebaseMessage)
                                  
                              }
                          }
                          
                      }
                      
                      
                      switch change.type {
                      case .added:
                          print(
                            "🔵 New document added: \(change.document.documentID)"
                          )
                          
                          self.coreDataUtils
                              .insertMessage(data: firebaseMessage)
                          
                          break
                          
                      case .modified:
                          print("🟠 Document modified: \(change.document.documentID)")
                          
                          self.coreDataUtils
                              .insertMessage(data: firebaseMessage)

                          break
                          
                      case .removed:
                          print("🔴 Document removed: \(change.document.documentID)")
                          self.coreDataUtils.removeMessage(id: messageId)
                          break;
                      }
                  }
                  
              }
              
          }

    }
    
    deinit {
        listener?.remove()
    }
}
