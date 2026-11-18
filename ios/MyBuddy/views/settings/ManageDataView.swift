//
//  ManageDataView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 24/07/2025.
//

import SwiftUI

struct ManageDataView: View {
    
    private let coreDataUtils = CoreDataUtils.shared
    
    var body: some View {
        List {
            
            Button {
                clearMessages()
            } label: {
                Text("Clear Messages").foregroundStyle(.red)
            }
            
            Button {
                clearChats()
            } label: {
                Text("Clear Chats").foregroundStyle(.red)
            }
            
            Button {
                clearFeed()
            } label: {
                Text("Clear Feed").foregroundStyle(.red)
            }
            
            Button {
                
                coreDataUtils.clearCoreData(entityName: "UserData")
                
            } label: {
                Text("Clear User Data").foregroundStyle(.red)
            }

        }
    }
    
    func clearMessages() {
        coreDataUtils.clearCoreData(entityName: "Messages")
    }
    
    func clearChats() {
        coreDataUtils.clearCoreData(entityName: "ChatMsg")
    }
    
    func clearFeed() {
        coreDataUtils.clearCoreData(entityName: "Feed")
    }
}

#Preview {
    ManageDataView()
}
