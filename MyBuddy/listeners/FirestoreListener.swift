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
    
    @Published var documents: [QueryDocumentSnapshot] = []
    
    init() {
        // listenToCollection()
    }
    
    func listenToCollection(name: String) {
        listener = db.collection(name)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let snapshot = snapshot else {
                    print("Error fetching snapshots: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }

                snapshot.documentChanges.forEach { change in
                    switch change.type {
                    case .added:
                        print("🔵 New document added: \(change.document.documentID)")
                    case .modified:
                        print("🟠 Document modified: \(change.document.documentID)")
                    case .removed:
                        print("🔴 Document removed: \(change.document.documentID)")
                    }
                }

                self.documents = snapshot.documents
            }
    }
    
    func listenToDoc(collectionName: String, documentId: String) {
        
        db.collection(collectionName)
            .document(documentId)
            .addSnapshotListener { documentSnapshot, error in
                guard let document = documentSnapshot, document.exists else {
                    print("Document does not exist or failed to fetch")
                    return
                }
                
                print("🟢 Document updated or fetched")
                let data = document.data()
                print("Data: \(data ?? [:])")
            }
    }
    
    deinit {
        listener?.remove()
    }
}
