//
//  ChatRoomViewModel.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 12/07/2025.
//

import FirebaseFirestore

struct ChatMessage: Codable, Identifiable {
    @DocumentID var id: String?
    let text: String
    let sender: String
    var isIncoming: Bool
    let timestamp: Date
}

class ChatRoomViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    private var db = Firestore.firestore()

    init() {
        db.collection("messages")
            .order(by: "timestamp")
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                self.messages = docs
                    .compactMap { try? $0.data(as: ChatMessage.self) }
                    .map({ ChatMessage in
                        var chat = ChatMessage
                        chat.isIncoming = true
                        print(chat)
                        return chat
                    })
            }
    }

    func sendMessage(text: String, sender: String) {
        let msg = ChatMessage(
            text: text,
            sender: sender,
            isIncoming: true,
            timestamp: Date()
        )
        
        
        
        try? db
            .collection("messages")
            .addDocument(
                from: msg,
                encoder: Firestore.Encoder(),
                completion: { error in
                    if let error = error {
                    } else {
                    }
                }
            )
        
        
    }
}
