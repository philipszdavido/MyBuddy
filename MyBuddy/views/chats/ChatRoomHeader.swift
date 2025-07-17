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

    var body: some View {
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
                Text("Save M")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("You")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Menu {
                Button {
                    coreDataUtils.clearCoreData(entityName: "Message")
                } label: {
                    Text("Clr Msg")
                }
                
                Button {
                    coreDataUtils.clearCoreData(entityName: "ChatMsg")
                } label: {
                    Text("Clr CMsg")
                }
            } label: {
                Label("", systemImage: "ellipsis")
            }

//            HStack(spacing: 20) {
//                Image(systemName: "video.fill")
//                Image(systemName: "phone.fill")
//            }
//            .foregroundColor(.green)
        }
        .padding()
        .background(Color.black)
        .frame(maxWidth: .infinity)
        
        //Divider()
    }
}

#Preview {
    ChatRoomHeader()
}
