// AI Buddy is disabled in this build: nothing in the app links to it, it returns placeholder replies,
// and the OpenAI call has no key (a key must never ship in the app; use a server-side proxy).
// Define the compilation condition AI_BUDDY to compile it again.
#if AI_BUDDY
//
//  ChatView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 26/06/2025.
//

import SwiftUI

// MARK: - ChatView
struct AIChatView: View {

    // MARK: - Message Model
    struct Message: Identifiable {
        let id = UUID()
        let text: String
        let isUser: Bool
    }

    @State private var messages: [Message] = [
        Message(text: "Hello! How can I help you today?", isUser: false)
    ]
    @State private var inputText = ""

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            HStack {
                                if message.isUser { Spacer() }
                                Text(message.text)
                                    .padding()
                                    .background(message.isUser ? Color.blue : Color.gray.opacity(0.5))
                                    //.foregroundColor(message.isUser ? .white : .black)
                                    .cornerRadius(16)
                                    .frame(maxWidth: 250, alignment: message.isUser ? .trailing : .leading)
                                if !message.isUser { Spacer() }
                            }
                            .padding(.horizontal)
                            .id(message.id)
                        }
                    }
                }
                .onChange(of: messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 12) {
                TextField("Type a message", text: $inputText)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Chat")
    }

    func sendMessage() {
        guard !inputText.isEmpty else { return }
        let userMessage = Message(text: inputText, isUser: true)
        messages.append(userMessage)

        let placeholder = Message(text: "Buddy is typing...", isUser: false)
        messages.append(placeholder)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let index = messages.firstIndex(where: { $0.text == "Buddy is typing..." }) {
                messages[index] = Message(text: "That's interesting! Tell me more.", isUser: false)
            }
            
            callOpenAI(prompt: inputText, completion: { result in
                debugLog(result)
                messages += [Message(text: result, isUser: false)]
            })
        }

        inputText = ""
    }
}

#Preview {
    AIChatView()
}
#endif
