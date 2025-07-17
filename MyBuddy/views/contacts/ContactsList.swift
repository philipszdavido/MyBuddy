//
//  ContactsList.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 14/07/2025.
//

import SwiftUI
import CoreData

struct ContactsList: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.timestamp, ascending: true)],
        animation: .default
    ) private var contacts: FetchedResults<Contact>
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    ) private var userData: FetchedResults<UserData>
    
    
    @State var present = false
    
    var body: some View {
        
        List {
            
            ForEach(contacts, id: \.id) { contact in
                
                NavigationLink {
                    if let currentUserPhoneNumber = userData.first?.phoneNumber, let currentUserId = userData.first?.id {
                        
                        
                        let otherUserId = contact.phoneNumber;
                        let chatId = [String(currentUserPhoneNumber), String(otherUserId)].sorted().joined(
                            separator: "_"
                        )
                        let recipientUserId = contact.id ?? ""
                        
                        ChatRoomView(
                            chatId: chatId,
                            currentUserId: currentUserId,
                            recipientUserId: recipientUserId
                        )
                        
                    }
                    
                } label: {
                    HStack(spacing: 9) {
                        Circle()
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading) {
                            Text(contact.displayName ?? "")
                            Text("\(String(contact.phoneNumber))")
                        }
                    }
                }
                
                
            }
        }
    }
}

#Preview {
    
    let persistenceController = PersistenceController.shared

    NavigationStack {
        ContactsList()
    }
    .environment(
        \.managedObjectContext,
         PersistenceController.preview.container.viewContext
    )
        .environmentObject(AuthViewModel())
}
