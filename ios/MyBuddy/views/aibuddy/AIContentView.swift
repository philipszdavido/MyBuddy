// AI Buddy is disabled in this build: nothing in the app links to it, it returns placeholder replies,
// and the OpenAI call has no key (a key must never ship in the app; use a server-side proxy).
// Define the compilation condition AI_BUDDY to compile it again.
#if AI_BUDDY
//
//  AIContentView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 13/07/2025.
//

import SwiftUI

struct AIContentView: View {
    var body: some View {
        TabView {
            AIBuddyChatView()
                .tabItem { Label("Chat", systemImage: "message") }
            
            CheckInView()
                .tabItem { Label("Check-in", systemImage: "sun.max") }
            
            ReminderView()
                .tabItem { Label("Reminders", systemImage: "clock") }
            
            DiscussionView()
                .tabItem { Label("Reflect", systemImage: "brain.head.profile") }
        }
    }
}

#Preview {
    AIContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
#endif
