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
    @EnvironmentObject var contactListVM: ContactListViewModel
    @State var selected = 1
    
    var body: some View {
        TabView(selection: $selected) {
            
            NavigationStack {
                ChatListView()
            }
            .tabItem {
                Label("Chats", systemImage: "message.fill")
            }
            .tag(1)
            
            NavigationStack {
                FeedListView()
            }
            .tabItem {
                Label("Feed", systemImage: "newspaper.fill")
            }
            
            NavigationStack {
                ContactsList()
            }
            .tabItem {
                Label("Contacts", systemImage: "person.2.circle")
            }
            .tag(2)
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(3)
        }
        .onAppear {
            contactListVM.startPhotoWatcher()
        }
        .onDisappear {
            contactListVM.stopPhotoWatcher()
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

