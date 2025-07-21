//
//  MediaChatSheetView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 18/07/2025.
//

import SwiftUI
import Combine

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
            )).padding(.top, 1)
            
        } else {
            
            ChatMediaSheetView(selectedImage: selectedImage)
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
    private let chatRoomViewModel = ChatRoomViewModel()
    @EnvironmentObject var chatDetails: ChatDetails

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
                        onSend()
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
    
    func onSend() {
        
        let messageText = String(text)
        
        // upload image to storage
        if let selectedImage {
            
            DispatchQueue.main.async {
                
                chatRoomViewModel.uploadToCloudinary(image: selectedImage) { result, imageData in
                    switch result {
                    case .success(let resultURL):
                        if let imageData {
                            
                            // ✅ Ensure these updates happen on the main thread
                            chatDetails.mediaUrl = resultURL
                            chatDetails.data = imageData
                            chatDetails.messageText = messageText
                            
                            // update core data
                            chatRoomViewModel.sendMediaMessage(
                                imageData: imageData,
                                chatDetails: chatDetails
                            )
                            print(chatDetails.messageText, text, messageText)
                            
                            
                        }
                    case .failure(let error):
                        print("Upload failed:", error)
                    }
                    
                }
                
            }
        }
        
        text = ""
        dismiss()
        
    }
    
}

#Preview {
    MediaChatSheetView()
}

#Preview {
    ChatMediaSheetView(selectedImage: UIImage(named: "bg") ?? UIImage())
}

