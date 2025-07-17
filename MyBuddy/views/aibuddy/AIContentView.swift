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
