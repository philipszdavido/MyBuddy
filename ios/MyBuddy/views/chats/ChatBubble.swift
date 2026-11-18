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
    
    private var deliveryState: DeliveryState {
        DeliveryState.resolve(sent: message.sent, rawState: message.deliveryState)
    }

    var body: some View {
        HStack {
            
            if isUser {
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                
                if let media = message.media, let type = media.type {
                    if type == "image" {
                        
                        if let imageData = media.mediaData,
                           let uiImage = ImageMemoryCache.shared.image(
                                key: media.id ?? "", data: imageData, maxPixel: 800) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .onTapGesture {
                                    isPresented = true
                                }
                        }
                        
                    }
                }
                
                if isLink, let linkURL = URL.safeWebLink(text) {
                    Link(text, destination: linkURL)
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
                    
                    if isUser {
                        switch deliveryState {
                        case .sent:
                            Image(systemName: "checkmark")
                                .foregroundStyle(.white)
                                .font(.caption2)
                                .accessibilityLabel("Sent")
                        case .sending:
                            Image(systemName: "clock")
                                .foregroundStyle(.white)
                                .font(.caption2)
                                .accessibilityLabel("Sending")
                        case .failed:
                            Button {
                                if let id = message.id { ChatRoomViewModel.shared.retry(messageID: id) }
                            } label: {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.footnote)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("Failed to send")
                            .accessibilityHint("Double tap to retry")
                        }
                    }
                    
                }
                .padding(.top)
                
                
            }
            .padding()
            .background(isUser ? Color.chatGreen : Color.chatGray)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            if !isUser {
                Spacer()
            }
            
        }
        .padding(.leading, isUser ? 60 : 10)
        .padding(.trailing, 10)
        .contextMenu {
            if isUser, deliveryState == .failed, let id = message.id {
                Button("Retry") { ChatRoomViewModel.shared.retry(messageID: id) }
                Button("Delete", role: .destructive) { ChatRoomViewModel.shared.discard(messageID: id) }
            }
        }
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
