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
    
    var body: some View {
        TabView(selection: /*@START_MENU_TOKEN@*//*@PLACEHOLDER=Selection@*/.constant(1)/*@END_MENU_TOKEN@*/) {
            
            ChatListView()
                .tabItem {
                    VStack {
                        Image(systemName: "message.fill")
                        Text("Chats")
                    }
                }.tag(1)
            
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

