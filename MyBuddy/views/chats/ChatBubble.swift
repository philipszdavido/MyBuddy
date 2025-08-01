//
//  ChatBubble.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 17/07/2025.
//

import SwiftUI
import UIKit

struct ChatBubble: View {
    
    let text: String
    let time: Date
    var isLink = false
    var isUsername = false
    
    var isUser: Bool
    @ObservedObject var message: Message
    
    @State var isPresented: Bool = false
    
    var body: some View {
        HStack {
            
            if isUser {
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                
                if let media = message.media, let type = media.type {
                    if type == "image" {
                        
                        if let imageData = media.mediaData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .onTapGesture {
                                    isPresented = true
                                }
                        }
                        
                    }
                }
                
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
                
                HStack {
                    
                    Text(time.formatted(date: .abbreviated, time: .standard))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    //.frame(maxWidth: .infinity, alignment: .trailing)
                    
                    if isUser {
                        if message.sent {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.white)
                                .font(.caption2)
                        } else {
                            Image(systemName: "clock")
                                .foregroundStyle(.white)
                                .font(.caption2)
                        }
                    }
                    
                }
                .padding(.top)
                
                
            }
            .padding()
            .background(isUser ? Color.chatGreen : Color.gray)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            //.frame(maxWidth: 300, alignment: .leading)

            if !isUser {
                Spacer()
            }
        }
        .padding(.leading, isUser ? 60 : 10)
        .padding(.trailing, 10)
        .fullScreenCover(isPresented: $isPresented) {
            isPresented = false
        } content: {
            
            if let media = message.media {
                ViewMedia(media: media) {
                    isPresented = false
                }
            }
            
        }


    }
}

#Preview {
    
    let context = PersistenceController.preview.container.viewContext

    let msg = Message(context: context)
    msg.sent = true

    let msg2 = Message(context: context)

    let media = Media(context: context)

    media.type = "jpg"
    media.mediaData = Mock.generateMockImageData()
    media.type = "image"

    // Connect media to message if needed
    msg.media = media

    return VStack {
        ChatBubble(
            text: "Hello",
            time: .now,
            isUser: true,
            message: msg2
        )
        ChatBubble(
            text: "Hello nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection",
            time: .now,
            isUser: true,
            message: msg
        )
        ChatBubble(
            text: "I am fine nw_connection_copy_connected_remote_endpoint_block_invoke [C8] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection",
            time: .now,
            isUser: false,
            message: msg
        )
    }
}
