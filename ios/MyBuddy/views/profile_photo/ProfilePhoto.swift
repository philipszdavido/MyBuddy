//
//  ProfilePhoto.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 25/07/2025.
//

import SwiftUI

struct ProfilePhoto: View {

    @ObservedObject var contact: Contact;
    var width: Int
    var height: Int

    var body: some View {
        // Same look as everywhere else: photo, or initials on the person's own colour.
        AvatarView(
            user: UserSummary(
                id: contact.id ?? String(contact.phoneNumber),
                username: nil,
                displayName: contact.displayName ?? "",
                avatarURL: contact.photo?.url.flatMap(URL.init(string:)),
                isVerified: false
            ),
            size: CGFloat(width)
        )
    }

    var initials: String {
        let name = (contact.displayName ?? "")
        let nameParts = name.split(separator: " ")
        
        if nameParts.isEmpty {
            return ""
        }
        
        if nameParts.count == 1 {
            return String(nameParts[0].first!).uppercased()
        }
        
        // Get first character of first and second name parts
        let firstInitial = nameParts[0].first ?? Character("")
        let secondInitial = nameParts[1].first ?? Character("")
        return String(firstInitial).uppercased() + String(secondInitial).uppercased()
    }

}

#Preview {

    let contact = Contact(
        context: PersistenceController.preview.container.viewContext
    )
    
    contact.displayName = "Nnamdi"
    contact.phoneNumber = 99876655443221
    
    return VStack {
        ProfilePhoto(contact: contact, width: 50, height: 50)
        
        ProfilePhoto(contact: contact, width: 20, height: 20)
    }
}
