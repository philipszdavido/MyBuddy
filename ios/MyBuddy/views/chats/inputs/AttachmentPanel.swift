//
//  AttachmentPanel.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 23/07/2025.
//

import SwiftUI

struct AttachmentPanel: View {
    var onClose: () -> Void
    var onSend: () -> Void
    var onImageSend: (UIImage?, String) -> Void

    @State var isPresented = false

    var body: some View {
        VStack {
            HStack {
                Text("Attachment Options")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    onClose()
                }
            }
            .padding()
            
            HStack {
                Button(action: {
                    // Action for file
                }) {
                    Label("File", systemImage: "doc")
                }
                Spacer()
                Button(action: {
                    // Action for image
                    isPresented = true
                }) {
                    Label("Photo", systemImage: "photo")
                }
                Spacer()
                Button(action: {
                    // Action for camera
                    isPresented = true
                }) {
                    Label("Camera", systemImage: "camera")
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 10)
        .background(Material.ultraThin)
        
        .fullScreenCover(isPresented: $isPresented) {
            isPresented = false
        } content: {
            MediaChatSheetView(onImageSend: onImageSend)
                .presentationDetents([.fraction(0.8), .large])
                .presentationDragIndicator(.visible)
            
        }
    }
}


#Preview {
    AttachmentPanel(onClose: {}, onSend: {}) { uIImage, text in
        
    }
}
