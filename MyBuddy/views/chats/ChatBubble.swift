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
    var message: Message
    
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
        .padding(.leading, isUser ? 60 : 10)
        .padding(.trailing, 10)
    }
}

func generateMockImageData() -> Data? {
    let size = CGSize(width: 100, height: 100)
    let renderer = UIGraphicsImageRenderer(size: size)
    
    let image = renderer.image { context in
        // Draw a background color
        UIColor.systemBlue.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        
        // Optional: Draw some text on it
        let text = "Hi"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30),
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textOrigin = CGPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        )
        text.draw(at: textOrigin, withAttributes: attributes)
    }
    
    return image.jpegData(compressionQuality: 0.8)
}

let data = Data(base64Encoded: """
data:image/jpeg;base64,/9j/4QDKRXhpZgAATU0AKgAAAAgABgESAAMAAAABAAEAAAEaAAUAAAABAAAAVgEbAAUAAAABAAAAXgEoAAMAAAABAAIAAAITAAMAAAABAAEAAIdpAAQAAAABAAAAZgAAAAAAAAA3AAAAAQAAADcAAAABAAeQAAAHAAAABDAyMjGRAQAHAAAABAECAwCgAAAHAAAABDAxMDCgAQADAAAAAQABAACgAgAEAAAAAQAAAAygAwAEAAAAAQAAABKkBgADAAAAAQAAAAAAAAAAAAD/2wCEAAEBAQEBAQIBAQIDAgICAwQDAwMDBAUEBAQEBAUGBQUFBQUFBgYGBgYGBgYHBwcHBwcICAgICAkJCQkJCQkJCQkBAQEBAgICBAICBAkGBQYJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCf/dAAQAAf/AABEIABIADAMBIgACEQEDEQH/xAGiAAABBQEBAQEBAQAAAAAAAAAAAQIDBAUGBwgJCgsQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+gEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoLEQACAQIEBAMEBwUEBAABAncAAQIDEQQFITEGEkFRB2FxEyIygQgUQpGhscEJIzNS8BVictEKFiQ04SXxFxgZGiYnKCkqNTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqCg4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2dri4+Tl5ufo6ery8/T19vf4+fr/2gAMAwEAAhEDEQA/APt3Rv8AgoN4D0v9sf4l/CH9tjX38AeNbKystVj8HadqEM1w+pMwnltrbUZJ1slD28iS/ZJRHMIlLEuHCro+GP8Agu1F+zvZTfDPwm3gGxtbaeSTy/HXja3j10sxwWuo7SJ7dDwMLG7gDgkNuVf5zP2tND+Hvx7/AGi/iX8fPhj4H8T/AAr0jxPPaeGLC11PThBpmq3V5qlrYa9aS3lpDItlNHMYrZbid2KyRyoR5sLInP8Ahj9gLTdc0GO1uta8XX1ppFzfaVYnw54Tl1uxhtrK9ngWAaiWEdzLEyskrwpEgcFTGsivn4HMHChGNRTaW19Ffr1g19yR/YPBOLrZrjMRgcThKcrWfJapNU+T3GoqOIpytra8pz0Stoz/0Pm/9uXxBrz/ALDP7D+nte3Bg8Rn4WXOrR+Y2y/mvv7WvruS6XOJnuLv/SZmk3GSb942X5r+rb/g3pllb9hXxHasxMVt8T/HccSZ+WNP7duW2oOirkk4HGSa/ky/bj/5Mk/YG/65fCH/ANJdWr+sn/g3n/5Mc8Vf9lS8d/8Ap7uK5Jf7zbyO+KXsPn+h/9k=                              
"""
)

#Preview {
    let context = PersistenceController.preview.container.viewContext

    let msg = Message(context: context)
    let media = Media(context: context)

    media.type = "jpg"
    media.mediaData = generateMockImageData()

    // Connect media to message if needed
    msg.media = media

    return VStack {
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
