//
//  ChatRoomHeader.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 17/07/2025.
//

import SwiftUI

struct ChatRoomHeader: View {
    
    private let coreDataUtils = CoreDataUtils.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var currentUserPhoneNumber: Int64
    var recipientUserPhoneNumber: Int64
    var contact: UserProfile

    var body: some View {
        
        let headerDisplay = contact.displayName
        
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    //.font(.system(size: 20, weight: .semibold))
            }
            
            Circle()
                .fill(Color.purple)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading) {
                Text(headerDisplay)
                    .font(.headline)
                    //.foregroundColor(.white)
                    .foregroundTheme(colorScheme: colorScheme)
//                Text("You")
//                    .font(.subheadline)
//                    .foregroundColor(.gray)
            }
            
            Spacer()
        

//            HStack(spacing: 20) {
//                Image(systemName: "video.fill")
//                Image(systemName: "phone.fill")
//            }
//            .foregroundColor(.green)
        }
        .padding()
        //.background(Color.black)
        .backgroundTheme(colorScheme: colorScheme)
        .frame(maxWidth: .infinity)
        
        Divider()
    }
}

struct ChatRoomHeader_Preview: View {
            
    var body: some View {

        let contact: Contact = Contact(
            context: PersistenceController.preview.container.viewContext
        )

        contact.phoneNumber = 787878
        contact.id = UUID().uuidString
        contact.timestamp = .now
        contact.displayName = "Nnamdi"

        return ChatRoomHeader(
            currentUserPhoneNumber: 7867676,
            recipientUserPhoneNumber: 89767565546565,
            contact: UserProfile(from: contact)
        )
    }
}

#Preview {
    
    ChatRoomHeader_Preview()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    
}
