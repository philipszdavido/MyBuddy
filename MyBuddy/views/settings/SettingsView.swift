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
                Section {
                    HStack {
                        Circle()
                            .frame(
                                width: 40,
                                height: 40,
                                alignment: Alignment.leading
                            )
                        VStack(alignment: .leading) {
                            Text(user.displayName ?? "No name")
                            
                            // Text(user.id ?? "").font(.subheadline)
                            
                            Text(String(user.phoneNumber)).font(.subheadline)
                            
                            Text(user.email ?? "No email")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
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

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AuthViewModel.shared)
}
