//
//  FeedViewModel.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 21/07/2025.
//

import Foundation
import Firebase
import FirebaseFirestore


class FeedViewModel: ObservableObject {
    static let shared = FeedViewModel()
    private var db = Firestore.firestore()
    private let coreDataUtils = CoreDataUtils.shared
    private let listener = FirestoreListener.shared
    
    let timestamp = FieldValue.serverTimestamp()

    func insertFeed(
        content: String,
        completion: @escaping (Error?) -> Void
    ) {
                
        DispatchQueue.main.async {
            
            let batch = self.db.batch()

            guard let userData = self.coreDataUtils.fetchUserData() else { return }

            let contacts = self.coreDataUtils.loadContacts()
            
            let post: [String: Any] = [
                "content" : content,
                "likes": 0,
                "dislikes": 0
            ]
            
            for contact in contacts {
                
                self.fanOutPostToContacts(
                    batch: batch,
                    contactId: String(contact.phoneNumber),
                    feedOwnerId: userData.phoneNumber,
                    post: post,
                    completion: { error in
                        
                    }
                )
                
            }
            
            batch.commit { error in
                if let error = error {
                    print("Error fanning out post: \(error.localizedDescription)")
                    completion(error)
                } else {
                    print("Successfully fanned out post.")
                    completion(nil)
                }
            }
            
        }
        

    }
    
    func fanOutPostToContacts(
        batch: WriteBatch,
        contactId: String,
        feedOwnerId: Int64,
        post: [String: Any],
        completion: @escaping (Error?) -> Void
    ) {
        
        let feedRef = db
            .collection("user_feed")
            .document(contactId)
            .collection("posts")
            .document()
        
        var postData = post
        postData["feedOwnerId"] = String(feedOwnerId)
        postData["timestamp"] = timestamp
        
        batch.setData(postData, forDocument: feedRef)
        
    }
    
    func listenToFeed() {

        // /user_feed/1234567890/posts/dH4oRCEW3JQCv6ILAmsG

        let contacts = coreDataUtils.loadContacts()

        for contact in contacts {
            
            listener
                .listenToCollection(
                    name: "/user_feed/" + String(contact.phoneNumber) + "/posts"
                ) { documentChangeType, queryDocumentSnapshot in
                    
                    let data = queryDocumentSnapshot.data()
                    
                    let id = queryDocumentSnapshot.documentID
                    
                    let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                    let feedOwnerId = data["feedOwnerId"] as? String
                    let content = data["content"] as? String
                    let likes = data["likes"] as? Int64
                    let dislikes = data["dislikes"] as? Int64
                    
                    self.coreDataUtils.insertFeed(
                        id: id,
                        timestamp: timestamp,
                        feedOwnerId: Int64(feedOwnerId ?? ""),
                        content: content,
                        likes: likes,
                        dislikes: dislikes
                    )
                    
                }
            
        }

    }
    
    func likeFeed(contact: Contact, feedId: String) {
        
        let fields: [String: Any] = [
            "likes": FieldValue.increment(Int64(1))
        ]
        
        db
            .document(
                "/user_feed/" + String(contact.phoneNumber) + "/posts/" + feedId
            )
            .updateData(fields) { error in
                if let error {
                    return
                }
            }
    }
    
    func dislikeFeed(contact: Contact, feedId: String) {
        
        let fields: [String: Any] = [
            "dislikes": FieldValue.increment(Int64(1))
        ]
        
        db
            .document(
                "/user_feed/" + String(contact.phoneNumber) + "/posts/" + feedId
            )
            .updateData(fields) { error in
                if let error {
                    return
                }
            }
        
    }

    
}
