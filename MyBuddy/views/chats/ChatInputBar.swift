//
//  ChatInputBar.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 17/07/2025.
//

import SwiftUI
import Combine

struct ChatInputBar: View {
    @Binding var text: String
    var colorScheme: ColorScheme
    var onSend: () -> Void

    @StateObject private var keyboard = KeyboardResponder()

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))

                TextField("Message", text: $text)
                    .padding(10)
                    .background(colorScheme == .light ? Color(white: 0.9) : Color(white: 0.2))
                    .foregroundStyle(colorScheme == .light ? .black : .white)
                    .clipShape(Capsule())
                    .multilineTextAlignment(.leading)

                if !text.isEmpty {
                    Button {
                        onSend()
                        text = ""
                    } label: {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 24))
                    }
                } else {
                    Image(systemName: "camera")
                        .font(.system(size: 24))
                }
            }
            .padding()
            .background(colorScheme == .light ? .white : .black)
        }
        .padding(.bottom, keyboard.currentHeight)
        .animation(.easeOut(duration: 0.25), value: keyboard.currentHeight)
    }
}

#Preview {
    
    @Previewable @State var text = ""
    
    return ChatInputBar(text: $text, colorScheme: ColorScheme.dark, onSend: {})
}


struct _ChatInputBar: View {
    @Binding var text: String
    @Binding var showAttachmentSheet: Bool
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                showAttachmentSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20))
            }

            TextField("Message", text: $text)
                .padding(10)
                .background(colorScheme == .light ? Color(white: 0.9) : Color(white: 0.2))
                .foregroundStyle(colorScheme == .light ? .black : .white)
                .clipShape(Capsule())

            if !text.isEmpty {
                Button {
                    onSend()
                    text = ""
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20))
                }
            }
        }
        .padding()
        .background(colorScheme == .light ? .white : .black)
    }
}

struct AttachmentSheet: View {
    var body: some View {
        VStack {
            Capsule()
                .frame(width: 40, height: 5)
                .foregroundColor(.gray)
                .padding(.top, 8)

            Text("GIFs & Stickers")
                .font(.headline)
                .padding()

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                    ForEach(1...20, id: \.self) { index in
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 80)
                            .overlay(
                                Text("GIF \(index)")
                            )
                    }
                }
                .padding()
            }

            Spacer()
        }
        .presentationDetents([.medium, .large])
        .background(Color(UIColor.systemBackground))
    }
}

struct Test_ChatInputBar: View {
    
    @State var showAttachmentSheet = false
    @State var messageText = ""

    var body: some View {
        _ChatInputBar(
            text: $messageText,
            showAttachmentSheet: $showAttachmentSheet,
            //colorScheme: colorScheme,
            onSend: {
                
            }
        )
        .sheet(isPresented: $showAttachmentSheet) {
            AttachmentSheet()
        }
    }
}
#Preview {
    
    Test_ChatInputBar()

}
