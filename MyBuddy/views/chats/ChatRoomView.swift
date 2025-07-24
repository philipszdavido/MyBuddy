//
//  ChatRoomView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 12/07/2025.
//

import SwiftUI
import FirebaseFirestore
import CoreData

struct ChatRoomView: View {
    private let listener = FirestoreListener()
    private let chatRoomViewModel = ChatRoomViewModel()
    private let coreDataUtils = CoreDataUtils()
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @FetchRequest private var messages: FetchedResults<Message>
    
    @State private var messageText: String = ""
    @State private var showSendButton: Bool = false
    
    var chatId: String
    var currentUserId: String
    var recipientUserId: String
    var currentUserPhoneNumber: Int64
    var recipientUserPhoneNumber: Int64
    var contact: UserProfile
    @StateObject private var keyboard = KeyboardResponder()

    var body: some View {

        VStack {
            
            VStack(spacing: 0) {
                
                // Header
                ChatRoomHeader(
                    currentUserPhoneNumber: currentUserPhoneNumber,
                    recipientUserPhoneNumber: recipientUserPhoneNumber,
                    contact: contact
                )
                .frame(maxWidth: .infinity)
                
                // Chat ScrollView
                ChatListScroll(
                    chatId: chatId,
                    currentUserId: currentUserId,
                    recipientUserId: recipientUserId,
                    messages: Array(messages)
                )
                
                Spacer()
                
                // Bottom Input Bar
                ChatInputBar(
                    text: $messageText,
                    colorScheme: colorScheme,
                    onSend: {
                        chatRoomViewModel
                            .sendMessage(
                                chatId: chatId,
                                currentUserId: currentUserId,
                                recipientUserId: recipientUserId,
                                messageText: messageText,
                                recipientUserPhoneNumber: recipientUserPhoneNumber,
                                currentUserPhoneNumber: currentUserPhoneNumber
                            )
                    },
                    onImageSend: onMediaSend
                )
            }
            
        }
        .background(
            Image("bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
        .hideKeyboardOnTap()
        .navigationBarBackButtonHidden(true)
        .onAppear {
            
            listener.listenToMessages(chatId: chatId)
            
        }
    }
    
    var log: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("chatId: \(chatId)")
            Text("currentUserId: \(currentUserId)")
            Text("recipientUserId: \(recipientUserId)")
            Text("currentUserPhoneNumber: \(currentUserPhoneNumber)")
            Text("recipientUserPhoneNumber: \(recipientUserPhoneNumber)")
        }
        .font(.caption)
        .foregroundColor(.gray)
    }

    init(
        chatId: String,
        currentUserId: String,
        recipientUserId: String,
        currentUserPhoneNumber: Int64,
        recipientUserPhoneNumber: Int64,
        contact: UserProfile
    ) {
        self.chatId = chatId
        self.currentUserId = currentUserId
        self.recipientUserId = recipientUserId
        self.currentUserPhoneNumber = currentUserPhoneNumber
        self.recipientUserPhoneNumber = recipientUserPhoneNumber
        self.contact = contact
        
        let predicate = NSPredicate(format: "chatId == %@", chatId)
        _messages = FetchRequest<Message>(
            entity: Message.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Message.timestamp, ascending: true)],
            predicate: predicate
        )
        
    }
    
    func onMediaSend(_ selectedImage: UIImage?, _ text: String) {
        
        let messageText = String(text)
        
        // upload image to storage
        if let selectedImage {
            
            DispatchQueue.main.async {
                
                let chatDetails = ChatDetails(
                    chatId: chatId,
                    currentUserId: currentUserId,
                    recipientUserId: recipientUserId,
                    messageText: messageText,
                    recipientUserPhoneNumber: recipientUserPhoneNumber,
                    currentUserPhoneNumber: currentUserPhoneNumber
                )
                
                chatRoomViewModel.uploadToCloudinary(image: selectedImage) { result, imageData in
                    switch result {
                    case .success(let resultURL):
                        if let imageData {
                            
                            // ✅ Ensure these updates happen on the main thread
                            chatDetails.mediaUrl = resultURL
                            chatDetails.data = imageData
                            chatDetails.messageText = messageText
                            
                            // update core data
                            chatRoomViewModel.sendMediaMessage(
                                imageData: imageData,
                                chatDetails: chatDetails
                            )
                            
                            print(chatDetails.messageText, text, messageText)
                            
                            
                        }
                    case .failure(let error):
                        print("Upload failed:", error)
                    }
                    
                }
                
            }
        }
        
        
    }

}

struct ChatRoomView_Preview: View {
    var body: some View {
        let contact = Contact(context:  PersistenceController.preview.container.viewContext)
        contact.phoneNumber = 998765
        contact.id = UUID().uuidString
        contact.timestamp = .now

        return NavigationStack {
            ChatRoomView(
                chatId: "nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection",
                currentUserId: "nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection",
                recipientUserId: "nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection",
                currentUserPhoneNumber: 12323443,
                recipientUserPhoneNumber: 08978675,
                contact: UserProfile(from: contact)
            )
                .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        }
    }
}

#Preview {
    
    ChatRoomView_Preview()
}
