//
//  MediaChatSheetView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 18/07/2025.
//

import SwiftUI
import Combine

struct MediaChatSheetView: View {
    
    var onImageSend: (UIImage?, String) -> Void;
    
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
            )).padding(.top, 1)
            
        } else {
            
            ChatMediaSheetView(selectedImage: selectedImage, onImageSend: { uIImage, text in
                onImageSend(uIImage, text)
            })
                .padding(.top, 1)
                        
        }

    }
}

struct ChatMediaSheetView: View {
    
    var selectedImage: UIImage?
    @State private var text: String = ""
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var keyboard = KeyboardResponderV2()

    var onImageSend: (UIImage?, String) -> Void;

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
                    .aspectRatio(contentMode: .fit)
                    .imageScale(.large)
                    .ignoresSafeArea()
                
                Spacer()
                
                HStack(spacing: 12) {
                    
                    CapsuleTextEditor(text: $text, colorScheme: colorScheme)
                    
                    Button {
                        
                        onImageSend(
                            selectedImage,
                            text
                        )

                        text = ""
                        dismiss()

                    } label: {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 34))
                    }
                    
                }
                .padding()
                .padding(.bottom, 30)
                .background(colorScheme == .light ? .white : .black)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                
                .padding(.bottom, keyboard.keyboardHeight)
                .animation(.easeOut(duration: 0.25), value: keyboard.keyboardHeight)

            }
            .ignoresSafeArea()
            .hideKeyboardOnTap()
            
        }
    }
    
}

#Preview {
    MediaChatSheetView(onImageSend: { _, _ in })
}

#Preview {
    ChatMediaSheetView(
        selectedImage: UIImage(named: "bg") ?? UIImage(),
        onImageSend: { _, _ in }
    )
}

