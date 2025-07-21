//
//  ContentView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 5/3/24.
//

import SwiftUI
import CoreData
    
struct ContentView: View {
    
    @EnvironmentObject var auth: AuthViewModel
    @State var selected = 1
    
    var body: some View {
        TabView(selection: $selected) {
            
            ChatListView()
                .tabItem {
                    VStack {
                        Image(systemName: "message.fill")
                        Text("Chats")
                    }
                }.tag(1)
            
            FeedListView()
                .tabItem {
                    VStack {
                        Image(systemName: "newspaper.fill")
                        Text("Feed")
                    }
                }
            
            ContactsList()
                .tabItem {
                    VStack {
                        Image(systemName: "person.2.circle")
                        Text("Contacts")
                    }
                }.tag(2)
            
            SettingsView()
                .tabItem {
                    VStack {
                        Image(systemName: "gear")
                        Text("Settings")
                    }

                }.tag(3)
            
        }
    }
}

#Preview {
    
    let auth = AuthViewModel.shared

    NavigationStack {
        
        if auth.user != nil {
            ContentView()
                
        } else {
            WelcomeView()
        }
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    .environmentObject(auth)
    .environment(\.debugMode, true)
    
}

