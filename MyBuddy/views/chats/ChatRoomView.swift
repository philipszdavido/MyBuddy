//
//  ChatRoomView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 12/07/2025.
//

import SwiftUI
import FirebaseFirestore

struct ChatRoomView: View {
    private let db = Firestore.firestore()
    private let coreDataUtils = CoreDataUtils.shared
    @Environment(\.dismiss) var dismiss
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .forward)],
        animation: .default
    ) private var messages: FetchedResults<Message>

    @State private var messageText: String = ""
    @State private var showSendButton: Bool = false
    
    var chatId: String
    var currentUserId: String
    var recipientUserId: String
        
    var body: some View {

        ZStack {
            
            // Background image
            Image("bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {

                // Header
                ChatRoomHeader()
                    .frame(maxWidth: .infinity)

                // Chat ScrollView
                ChatListScroll(
                    chatId: chatId,
                    currentUserId: currentUserId,
                    recipientUserId: recipientUserId,
                    messages: Array(messages)
                )
                
                // Bottom Input Bar
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 24))
                    
                    TextField("Message", text: $messageText)
                        .padding(10)
                        .background(Color(white: 0.2))
                        .clipShape(Capsule())
                    
                    if !messageText.isEmpty {

                        Button {
                            
                            sendMessage()
                            messageText = ""
                            
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 24))
                        }
                        
                    }
                    else {
                        Image(systemName: "camera")
                            .font(.system(size: 24))
                    }
                }
                .padding()
                .background(Color.black)
                .foregroundColor(.white)
            }
            //.background(Color.black)
            //.preferredColorScheme(.dark)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            
             listenToMessages()

        }
    }
    
    func sendMessage() {

        let chatRef = db.collection("chats").document(chatId)
        
        let messageContent = messageText

        chatRef.getDocument { snapshot, error in
            
            let timestamp = Timestamp()
            
            if snapshot?.exists == false {
                
                // Chat doesn't exist – create it
                chatRef.setData([
                    "participants": [currentUserId, recipientUserId],
                    "lastMessage": messageContent,
                    "lastSenderId": currentUserId,
                    "lastTimestamp": timestamp,
                    "updatedAt": timestamp
                ])
                
                coreDataUtils.insertChatMsg(
                    id: chatId,
                    currentUserId: currentUserId,
                    recipientUserId: recipientUserId,
                    lastMessage: messageContent,
                    lastSenderId: currentUserId,
                    lastTimestamp: timestamp.dateValue(),
                    updatedAt: timestamp.dateValue()
                )
                
            } else {
                
                // Chat exists – update lastMessage
                chatRef.updateData([
                    "lastMessage": messageContent,
                    "lastSenderId": currentUserId,
                    "lastTimestamp": timestamp,
                    "updatedAt": timestamp
                ])
                
                coreDataUtils.insertChatMsg(
                    id: chatId,
                    currentUserId: currentUserId,
                    recipientUserId: recipientUserId,
                    lastMessage: messageContent,
                    lastSenderId: currentUserId,
                    lastTimestamp: timestamp.dateValue(),
                    updatedAt: timestamp.dateValue()
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
            
            coreDataUtils.insertMessage(
                id: messageRef.documentID,
                senderId: currentUserId,
                recipientId: recipientUserId,
                content: messageContent,
                timestamp: timestamp.dateValue(),
                seen: false
            )
            
        }

    }
    
    func listenToMessages() {
        
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
                  
                  let data = change.document.data()
                  let messageId = change.document.documentID
                                                                
                  let senderId = data["senderId"] as? String ?? ""
                  let recipientId = data["recipientId"] as? String ?? ""
                  let content = data["content"] as? String ?? ""

                  let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                  
                  let seen = data["seen"] as? Bool ?? true

                  switch change.type {
                  case .added:
                      print(
                       "🔵 New document added: \(change.document.documentID)"
                      )
                      
                      CoreDataUtils.shared
                          .insertMessage(
                            id: messageId,
                            senderId: senderId,
                            recipientId: recipientId,
                            content: content,
                            timestamp: timestamp,
                            seen: seen
                          )
                      break
                      
                  case .modified:
                      print("🟠 Document modified: \(change.document.documentID)")
                      
                      CoreDataUtils.shared
                          .insertMessage(
                            id: messageId,
                            senderId: senderId,
                            recipientId: recipientId,
                            content: content,
                            timestamp: timestamp,
                            seen: seen
                          )
                      break

                  case .removed:
                      print("🔴 Document removed: \(change.document.documentID)")
                      CoreDataUtils.shared.removeMessage(id: messageId)
                      break;
                  }
              }

              
          }

    }
    
}

//struct ChatRoomView_Previews: PreviewProvider {
//    static var previews: some View {
//        NavigationStack {
//            ChatRoomView(chatId: "", currentUserId: "", recipientUserId: "")
//                .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
//        }
//    }
//}

#Preview {
    NavigationStack {
        ChatRoomView(chatId: "nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection", currentUserId: "nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection", recipientUserId: "nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection")
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}

//                        ChatDateHeader("Fri 18. Apr")
//
//                        ChatBubble(text: """
//                     I'm old enough to be your father but I do admire your drive! Smart move on your part to become a plumber, a trade that is very lucrative. Be a student for life and never stop learning. Continue to develop yourself and grow.
//                    """, time: "7:26 AM")
//
//                        ChatBubble(text: "https://www.facebook.com/share/v/1Hfczkhs3p/?mibextid=wwXlfr", time: "6:05 PM", isLink: true)
//
//                        ChatDateHeader("Sat 19. Apr")
//                        ChatBubble(text: "@simone_christensen", time: "5:44 AM", isUsername: true)
//
//                        ChatDateHeader("Tue 22. Apr")
//                        ChatBubble(text: "I think anyone referring to themselves as high value is actually of no value", time: "4:28 AM")
//
//                        ChatDateHeader("Thu 24. Apr")
