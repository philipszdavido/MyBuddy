//
//  ChatListView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 12/07/2025.
//

import SwiftUI
import CoreData
import FirebaseFirestore

struct ChatListView: View {
    
    @StateObject var contactManager = ContactManager()
    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject var auth: AuthViewModel
    private let db = Firestore.firestore()
    
    @State var presentSheet: Bool = false
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.lastTimestamp, order: .forward)],
        animation: .default
    ) private var chats: FetchedResults<ChatMsg>
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    ) private var userData: FetchedResults<UserData>
    
    var body: some View {
        List {
            ForEach(chats) { chat in
                NavigationLink(
                    destination: ChatRoomView(
                        chatId: chat.id ?? "",
                        currentUserId: chat.currentUserId ?? "",
                        recipientUserId: chat.recipientUserId ?? ""
                    )
                ) {
                    HStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading) {
                            Text(chat.recipientUserId ?? "Unknown")
                                .font(.headline)
                            Text(chat.lastMessage ?? "")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(
                placement: ToolbarItemPlacement.navigationBarTrailing) {
                    Button {
                        presentSheet = true
                    } label: {
                        Image(systemName: "plus.circle")
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
                
                ContactsList()
                Spacer()
            }
        })
        .onAppear {
            listen()
        }
        
    }
    
    func listen() {
        
        if let currentUserId = userData.first?.id {
            
            db.collection("chats")
                .whereField("participants", arrayContains: currentUserId)
                .order(by: "updatedAt", descending: true)
                .addSnapshotListener {
                    snapshot,
                    error in
                    // Update chats in Core Data
                    print("ChatListView", snapshot, error)
                    
                    guard let snapshot = snapshot else {
                        print("Error fetching snapshots: \(error?.localizedDescription ?? "Unknown error")")
                        return
                    }
                    
                    snapshot.documentChanges.forEach { change in
                        
                        let data = change.document.data()
                        let chatId = change.document.documentID
                        
                        let participants = data["participants"] as? [String] ?? []
                        
                        let lastMessage = data["lastMessage"] as? String ?? ""
                        let lastSenderId = data["lastSenderId"] as? String ?? ""
                        let recipientUserId = participants[0] == currentUserId ? currentUserId : participants[1]
                        
                        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                        let lastTimestamp = (data["lastTimestamp"] as? Timestamp)?.dateValue() ?? Date()
                        
                        switch change.type {
                        case .added:
                            print(
                                "🔵 New document added: \(change.document.documentID)"
                            )
                            
                            CoreDataUtils.shared
                                .insertChatMsg(
                                    id: chatId,
                                    currentUserId: currentUserId,
                                    recipientUserId: recipientUserId,
                                    lastMessage: lastMessage,
                                    lastSenderId: lastSenderId,
                                    lastTimestamp: lastTimestamp,
                                    updatedAt: updatedAt
                                )
                            break
                        case .modified:
                            print("🟠 Document modified: \(change.document.documentID)")
                            
                            CoreDataUtils.shared
                                .insertChatMsg(
                                    id: chatId,
                                    currentUserId: currentUserId,
                                    recipientUserId: recipientUserId,
                                    lastMessage: lastMessage,
                                    lastSenderId: lastSenderId,
                                    lastTimestamp: lastTimestamp,
                                    updatedAt: updatedAt
                                )
                            break
                        case .removed:
                            print("🔴 Document removed: \(change.document.documentID)")
                            CoreDataUtils.shared.removeChatMsg(id: chatId)
                            break
                        }
                    }
                    
                    
                }
            
        }
        
    }
    
}

// MARK: - Preview
#Preview {
    let auth = AuthViewModel.shared

    NavigationStack {
        
        ChatListView()
    }
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(auth)
}
