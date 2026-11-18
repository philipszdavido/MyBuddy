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
    @EnvironmentObject var router: DeepLinkRouter
    
    var body: some View {
        TabView(selection: $router.selectedTab) {

            Group {
                // MyBuddy API: inbox with groups and message requests. Firebase: the Core Data chat list.
                if let messaging = AppContainer.shared.messagingRepository {
                    InboxView(repository: messaging, social: AppContainer.shared.socialRepository)
                } else {
                    NavigationStack { ChatListView() }
                }
            }
            .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
            .tag(AppTab.chats)

            NavigationStack {
                FeedListView()
            }
            .tabItem { Label("Feed", systemImage: "rectangle.stack") }
            .tag(AppTab.feed)

            NavigationStack {
                ContactsList()
            }
            .tabItem { Label("Contacts", systemImage: "person.2") }
            .tag(AppTab.contacts)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .onAppear {
            router.feedHandlesProfileAndPostLinks = AppContainer.shared.socialRepository != nil
            contactListVM.startPhotoWatcher()
            OutboxRetrier.shared.start(userID: auth.accountID)
            OutboxRetrier.shared.flush()
            router.routePendingToTab()   // cold launch from a link / notification tap
        }
        .onChange(of: router.pending) {
            router.routePendingToTab()
        }
        .task(id: auth.accountID) {
            // Live blocked-users list for the signed-in account; listener ends with the task.
            guard let uid = auth.accountID else { return }
            OutboxRetrier.shared.start(userID: uid)   // profile can load after the view appeared
            await BlockedUsersStore.shared.sync(userID: uid)
        }
        .onDisappear {
            contactListVM.stopPhotoWatcher()
            OutboxRetrier.shared.stop()
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
    .environmentObject(DeepLinkRouter())
    .environment(\.debugMode, true)
    
}
