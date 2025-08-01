//
//  SettingsView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 17/07/2025.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.colorScheme) var colorScheme
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .default
    ) private var userDatas: FetchedResults<UserData>

    var body: some View {
        
        List {
            
            ForEach(userDatas) { user in
                
                if let contact = CoreDataUtils.shared.getContactWithNumber(phoneNumber: user.phoneNumber),
                   let userId = user.id {
                    ContactSectionView(contact: contact, user: user, userId: userId)
                }
                                
            }
            
            Section {
                NavigationLink {
                    MediaListView()
                } label: {
                    Text("Media")
                }

            }
            
            Section {
                NavigationLink {
                    ManageDataView()
                } label: {
                    Text("Manage Data")
                }

            }
                        
            Section {
                Button {
                    auth.logout()
                } label: {
                    Text("Logout").foregroundStyle(.red)
                }
                
            }
        }
        .navigationTitle("Settings")
        .preferredColorScheme(colorScheme)
        
    }
}

struct ContactSectionView: View {
    @ObservedObject var contact: Contact
    let user: UserData
    let userId: String

    var body: some View {
        Section {
            
            NavigationLink {
                
                //if let contact, let userId = user.id {
                    EditProfileView(
                        contact: contact,
                        userId: userId
                    )
                //}
                
            } label: {
                HStack {
                    
                    //if let contact {
                        ProfilePhoto(contact: contact, width: 40, height: 40)
                    //}
                    
                    VStack(alignment: .leading) {
                        Text(user.displayName ?? "No name")
                                                        
                        Text(String(user.phoneNumber)).font(.subheadline)
                        
                        Text(user.email ?? "No email")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            
        }

    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AuthViewModel.shared)
}
