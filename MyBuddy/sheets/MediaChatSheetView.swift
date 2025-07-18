//
//  MediaChatSheetView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 18/07/2025.
//

import SwiftUI

struct MediaChatSheetView: View {
    
    enum ShowType {
        case media;
        case chat
    }
    
    @State var show: ShowType = .media
    @State private var selectedImage: UIImage?
    
    var body: some View {
        
        if show == .media {
            CameraView(selectedImage: Binding<UIImage?>(
                get: {
                    selectedImage ?? UIImage()
                },
                set: { uImage in
                    selectedImage = uImage
                    show = .chat
                }
            ))
        } else {
            ChatMediaSheetView(selectedImage: selectedImage)
        }

    }
}

struct ChatMediaSheetView: View {
    
    var selectedImage: UIImage?
    @State private var text: String = ""
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    var body: some View {
        if let image = selectedImage {
            VStack {
                // Top Bar
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    Spacer()
                    HStack(spacing: 12) {
//                        Button(action: {}) {
//                            Image(systemName: "circle.lefthalf.fill")
//                        }
//                        Button(action: {}) {
//                            Image(systemName: "bolt.badge.a")
//                        }
                    }
                    .padding(.trailing)
                }
                .padding(.horizontal)
                .padding(.top)
                Spacer()
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
                Spacer()
                
                HStack(spacing: 12) {
                    
                    CapsuleTextEditorV2(text: $text, colorScheme: colorScheme)
                    
                    Button {
                        // onSend()
                        text = ""
                    } label: {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 34))
                    }
                    
                }
                .padding()
                .padding(.bottom, 30)
                .background(colorScheme == .light ? .white : .black)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            }.ignoresSafeArea()
        }
    }
}

#Preview {
    MediaChatSheetView()
}

#Preview {
    ChatMediaSheetView(selectedImage: UIImage(named: "bg") ?? UIImage())
}
