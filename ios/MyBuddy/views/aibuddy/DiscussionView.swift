// AI Buddy is disabled in this build: nothing in the app links to it, it returns placeholder replies,
// and the OpenAI call has no key (a key must never ship in the app; use a server-side proxy).
// Define the compilation condition AI_BUDDY to compile it again.
#if AI_BUDDY
//
//  DiscussionView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 26/06/2025.
//

import SwiftUI

let questions = [
    "What are you grateful for today?",
    "If today was a movie, what genre would it be?",
    "What made you smile today?",
    "What’s something you’re looking forward to?"
]

struct DiscussionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Let’s Reflect 🧠")
                .font(.title)
            ForEach(questions.shuffled().prefix(1), id: \.self) {
                Text($0).font(.headline).padding()
            }
        }.padding()
    }
}

#Preview {
    DiscussionView()
}
#endif
