// AI Buddy is disabled in this build: nothing in the app links to it, it returns placeholder replies,
// and the OpenAI call has no key (a key must never ship in the app; use a server-side proxy).
// Define the compilation condition AI_BUDDY to compile it again.
#if AI_BUDDY
//
//  AIBuddyChatView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 13/07/2025.
//

import SwiftUI

struct AIBuddyChatView: View {
    @State private var messages: [String] = []
    @State private var inputText = ""

    var body: some View {
        VStack {
            ScrollView {
                ForEach(messages, id: \.self) { msg in
                    Text(msg).padding().background(Color.gray.opacity(0.2)).cornerRadius(8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                TextField("Say something...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Send") {
                    sendMessage()
                }
            }.padding()
        }.navigationTitle("Chat")
    }

    func sendMessage() {
        guard !inputText.isEmpty else { return }
        messages.append("You: \(inputText)")
        // Call OpenAI here
        messages.append("Buddy: Thinking...")

        // Placeholder reply
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            messages.removeLast()
            messages.append("Buddy: That's interesting! Tell me more.")
        }

        inputText = ""
    }
}

#Preview {
    AIBuddyChatView()
}
#endif
