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
    private let listener = FirestoreListener()
    private let chatViewModel = ChatRoomViewModel()
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.timestamp, order: .forward)],
        animation: .default
    ) private var messages: FetchedResults<Message>

    @State private var messageText: String = ""
    @State private var showSendButton: Bool = false
    
    var chatId: String
    var currentUserId: String
    var recipientUserId: String
    var currentUserPhoneNumber: Int64
    var recipientUserPhoneNumber: Int64
    var contact: Contact
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
                        chatViewModel
                            .sendMessage(
                                chatId: chatId,
                                currentUserId: currentUserId,
                                recipientUserId: recipientUserId,
                                messageText: messageText,
                                recipientUserPhoneNumber: recipientUserPhoneNumber,
                                currentUserPhoneNumber: currentUserPhoneNumber
                            )
                    }
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
                contact: contact
            )
                .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        }
    }
}

#Preview {
    
    ChatRoomView_Preview()
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


// Bottom Input Bar
//                HStack(spacing: 12) {
//                    Image(systemName: "plus.circle")
//                        .font(.system(size: 24))
//
//                    TextField("Message", text: $messageText)
//                        .padding(10)
//                        .background(
//                            colorScheme == .light
//                                ? Color(white: 0.9)
//                                : Color(white: 0.2)
//                        )
//                        .foregroundStyle(colorScheme == .light ? .black : .white)
//                        .clipShape(Capsule())
//                        .multilineTextAlignment(.leading)
//
//                    if !messageText.isEmpty {
//
//                        Button {
//
//                            sendMessage()
//                            messageText = ""
//
//                        } label: {
//                            Image(systemName: "paperplane.circle.fill")
//                                .font(.system(size: 24))
//                        }
//
//                    }
//                    else {
//                        Image(systemName: "camera")
//                            .font(.system(size: 24))
//                    }
//                }
//                .padding()
//                .background(colorScheme == .light ? .white : .black)
