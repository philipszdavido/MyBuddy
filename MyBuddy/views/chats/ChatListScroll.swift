//
//  ChatListScroll.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 17/07/2025.
//

import SwiftUI

struct ChatListScroll: View {
    
    var chatId: String
    var currentUserId: String
    var recipientUserId: String
    var messages: [Message]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    
                    
                    ForEach(messages) { message in
                        
                        if let timestamp = message.timestamp {
                            ChatDateHeader(timestamp)
                        }
                        
                        ChatBubble(
                            text: message.content ?? "",
                            time: message
                                .timestamp ?? .now,
                            isUser: message.senderId == currentUserId,
                            message: message
                        )
                    }
                    
                }
            }
            //.background(Color.black.edgesIgnoringSafeArea(.all))
            .onChange(of: messages.count) { _ in
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

#Preview {
    
    let context = PersistenceController.preview.container.viewContext
    
    let msg1 = Message(context: context)
    msg1.id = UUID().uuidString
    msg1.content = "Hey there nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection"
    msg1.senderId = "user1"
    msg1.timestamp = Date()
    
    let msg2 = Message(context: context)
    msg2.id = UUID().uuidString
    msg2.content = "Hello! nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection"
    msg2.senderId = "user2"
    msg2.timestamp = Date().addingTimeInterval(-60)
    
    return ChatListScroll(
        chatId: "3e3edd",
        currentUserId: "sdxsdxsds nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection",
        recipientUserId: "sdsded nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection",
        messages: [msg1, msg2]
    )
    
}
