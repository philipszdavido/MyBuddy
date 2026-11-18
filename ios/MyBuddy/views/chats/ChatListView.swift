//
//  ChatListView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 12/07/2025.
//

import SwiftUI
import CoreData

struct ChatListView: View {
    
    @StateObject var contactManager = ContactManager()
    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var router: DeepLinkRouter
    @State private var openChat: ChatMsg?
    @ObservedObject private var blockedUsers = BlockedUsersStore.shared
    private let coreDataUtils = CoreDataUtils.shared
    
    @State var presentSheet: Bool = false
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.lastTimestamp, order: .forward)],
        animation: .default
    ) private var chats: FetchedResults<ChatMsg>
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    ) private var userData: FetchedResults<UserData>

    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    ) private var contacts: FetchedResults<Contact>

    func numberToDisplay(chat: ChatMsg) -> Int64 {
        
        if let data = userData.first {
            if chat.lastSenderPhoneNumber == data.phoneNumber {
                return chat.recipientUserPhoneNumber
            }
        }
        
        return chat.currentUserPhoneNumber
    }
            
    private func chatRoom(for chat: ChatMsg, contact: Contact) -> some View {
        ChatRoomView(
            chatId: chat.id ?? "",
            currentUserId: chat.currentUserId ?? "",
            recipientUserId: chat.recipientUserId ?? "",
            currentUserPhoneNumber: chat.currentUserPhoneNumber,
            recipientUserPhoneNumber: chat.recipientUserPhoneNumber,
            contact: contact
        ).toolbar(.hidden, for: ToolbarPlacement.tabBar)
    }

    private func resolvePendingChat() {
        guard case .chat(let id)? = router.pending,
              let chat = chats.first(where: { $0.id == id }),
              chat.contact != nil else { return }
        router.consume()
        openChat = chat
    }

    var body: some View {
        List {
            ForEach(chats.filter { !blockedUsers.ids.contains($0.recipientUserId ?? "") }) { chat in
                                
                if let contact = chat.contact {

                    NavigationLink(
                        destination: chatRoom(for: chat, contact: contact)
                    ) {
                        HStack {
                            
                            ProfilePhoto(contact: contact, width: 44, height: 44)
                            
                            VStack(alignment: .leading) {
                                
                                Text(
                                    contact.displayName ?? contact.phoneNumber.description
                                )
                                .font(.headline)
                                
                                HStack {
                                    
                                    if let type = chat.type {
                                        if type == "image" {
                                            Text("🏞️")
                                        }
                                        if type == "video" {
                                            Text("📹")
                                        }
                                    }
                                    
                                    Text(chat.lastMessage ?? "")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                    
                                }
                            }
                        }
                    }
                    
                }
            }
        }
        .navigationTitle("Chats")
        .navigationDestination(item: $openChat) { chat in
            if let contact = chat.contact {
                chatRoom(for: chat, contact: contact)
            }
        }
        .onAppear { resolvePendingChat() }
        .onChange(of: router.pending) { resolvePendingChat() }
        .onChange(of: chats.count) { resolvePendingChat() }
        .task(id: router.pending) {
            // A link to a conversation that never syncs must not stay pending forever.
            guard router.pending != nil else { return }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if !Task.isCancelled, case .chat? = router.pending { router.consume() }
        }
        .toolbar {
            ToolbarItem(
                placement: ToolbarItemPlacement.navigationBarTrailing) {
                    Button {
                        presentSheet = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .accessibilityLabel("New chat")
                    }
                    
                }
        }
        .sheet(isPresented: $presentSheet, content: {
                VStack {
                    
                    HStack {
                        Spacer()
                        Button {
                            presentSheet = false
                        } label: {
                            Text("Done")
                        }
                    }
                    .padding()
                    
                    NavigationStack {
                        
                        ContactsList()
                    }
                    
                    Spacer()
                }
        })
        .task(id: userData.first?.id) {
            guard let currentUserId = userData.first?.id else { return }
            await ChatSyncService.shared.syncConversations(userID: currentUserId)
        }
        
    }
    
}

#Preview {
    
    let auth = AuthViewModel.shared

    NavigationStack {
        
        ChatListView()
    }
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(auth)
        .environmentObject(DeepLinkRouter())
    
}
