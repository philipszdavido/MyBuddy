//
//  ChatBubble.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 17/07/2025.
//

import SwiftUI

struct ChatBubble: View {
    
    let text: String
    let time: Date
    var isLink = false
    var isUsername = false
    
    var isUser: Bool
    
    var body: some View {
        HStack {
            
            if isUser {
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                if isLink {
                    Link(text, destination: URL(string: text)!)
                        .foregroundColor(.blue)
                        .font(.body)
                        .underline()
                } else if isUsername {
                    Text(text)
                        .foregroundColor(.cyan)
                        .font(.body)
                } else {
                    Text(text)
                        .foregroundColor(.white)
                        .font(.body)
                }
                
                Text(time.formatted(date: .abbreviated, time: .standard))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding()
            .background(isUser ? Color.green : Color.gray)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: 300, alignment: .leading)
            
            if !isUser {
                Spacer()
            }
        }
        .padding(.leading, 60)
        .padding(.trailing, 10)
    }
}

#Preview {
    ChatBubble(text: "Hello nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection", time: .now, isUser: true)
    ChatBubble(text: "I am fine nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection", time: .now, isUser: false)
}
