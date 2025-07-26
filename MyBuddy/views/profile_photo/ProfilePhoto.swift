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
        
        if let photo = contact.photo, let url = photo.url {
//            if let uiImage = photo.mediaData {
//                if let uiImage = UIImage(data: uiImage) {
//                    Image(uiImage: uiImage)
//                        .resizable()
//                        .scaledToFill()
//                        .frame(width: CGFloat(width), height: CGFloat(height))
//                        .clipShape(Circle())
//                }
//            } else {
                CachedAsyncImage(
                    url: URL(string: url)!,
                    width: width,
                    height: height
                )
            //}
        } else {
            Circle()
                .fill(.blue)
                .frame(width: CGFloat(width), height: CGFloat(height))
                .overlay {
                    Text(initials)
                        .bold()
                        .font(.headline)
                }
        }
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
