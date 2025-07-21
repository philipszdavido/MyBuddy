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
    private let listener = FirestoreListener.shared
    
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
    
    func findContact(chat: ChatMsg) -> Contact {
        
        let number = numberToDisplay(chat: chat)
        
        let contact = contacts.first { Contact in
            Contact.phoneNumber == number
        }
        
        if let contact {
            return contact
        } else {
            let contact = Contact(context: managedObjectContext)
            contact.displayName = String(number)
            contact.phoneNumber = number
            contact.id = UUID().uuidString
            contact.timestamp = .now
            return contact
        }
        
    }
        
    var body: some View {
        List {
            ForEach(chats) { chat in
                
                let contact = findContact(chat: chat)
                
                NavigationLink(
                    destination: ChatRoomView(
                        chatId: chat.id ?? "",
                        currentUserId: chat.currentUserId ?? "",
                        recipientUserId: chat.recipientUserId ?? "",
                        currentUserPhoneNumber: chat.currentUserPhoneNumber,
                        recipientUserPhoneNumber: chat.recipientUserPhoneNumber,
                        contact: contact
                    )
                ) {
                    HStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading) {
                            
                            Text(
                                contact.displayName ?? contact.phoneNumber.description
                            )
                            .font(.headline)
                            
                            HStack {

                                if let type = chat.type {
                                    if type == "image" {
                                        Text("🏞️")
                                        // Image(systemName: "photo")
                                    }
                                    if type == "video" {
                                        Text("📹")
                                        // Image(systemName: "video.circle")
                                    }
                                }

                                Text(chat.lastMessage ?? "")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                
                            }
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
            
            listener.listenToParticipants(currentUserId: currentUserId)
            
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
}
