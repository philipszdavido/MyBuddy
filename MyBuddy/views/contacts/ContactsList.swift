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
        sortDescriptors: [],
        animation: .default
    ) private var contacts: FetchedResults<Contact>
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    ) private var userData: FetchedResults<UserData>
    
    
    @State var present = false
    
    var body: some View {
        
        List {
            
            ForEach(contacts) { contact in
                if contact.phoneNumber != userData.first?.phoneNumber {
                    
                    NavigationLink {
                        if let currentUserPhoneNumber = userData.first?.phoneNumber, let currentUserId = userData.first?.id {
                            
                            
                            let contactPhoneNumber = contact.phoneNumber;
                            let chatId = [String(currentUserPhoneNumber), String(contactPhoneNumber)].sorted().joined(
                                separator: "_"
                            )
                            let recipientUserId = contact.id ?? ""
                            
                            ChatRoomView(
                                chatId: chatId,
                                currentUserId: currentUserId,
                                recipientUserId: recipientUserId,
                                currentUserPhoneNumber: currentUserPhoneNumber,
                                recipientUserPhoneNumber:
                                    contactPhoneNumber,
                                contact: contact
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
}

#Preview {
    
    NavigationStack {
        ContactsList()
    }
    .environment(
        \.managedObjectContext,
         PersistenceController.preview.container.viewContext
    )
        .environmentObject(AuthViewModel())
}
