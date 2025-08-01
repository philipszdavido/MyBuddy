//
//  ChatInputBar.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 17/07/2025.
//

import SwiftUI
import Combine

struct ChatInputBar: View {
    @Binding var text: String
    var colorScheme: ColorScheme
    var onSend: () -> Void
    var onImageSend: (UIImage?, String) -> Void
    
    @State var isSheetPresented = false
    
    @State var isPresented = false

    var body: some View {

        VStack {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    
                    Button {
                        withAnimation {
                            isSheetPresented.toggle()
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 24))
                    }
                    
                    CapsuleTextEditor(text: $text, colorScheme: colorScheme)
                    
                    if !text.isEmpty {
                        Button {
                            onSend()
                            text = ""
                        } label: {
                            Image(systemName: "paperplane.circle.fill")
                                .font(.system(size: 24))
                        }
                    } else {
                        Image(systemName: "camera")
                            .font(.system(size: 24))
                            .onTapGesture {
                                isPresented = true
                            }
                    }
                }
                .padding()
                .background(colorScheme == .light ? .white : .black)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .fullScreenCover(isPresented: $isPresented) {
                isPresented = false
            } content: {
                MediaChatSheetView(onImageSend: onImageSend)
                    .presentationDetents([.fraction(0.8), .large])
                    .presentationDragIndicator(.visible)
                
            }
            
            if isSheetPresented {
                VStack {
                    AttachmentPanel(onClose: {
                        isSheetPresented = false
                    }, onSend: {
                        
                    }) { uiImage, text in
                        onImageSend(uiImage, text)
                    }
                }
            }
        }
        
        
    }
}

#Preview {
    
    @Previewable @State var text = ""
    
    return ChatInputBar(
        text: $text,
        colorScheme: ColorScheme.dark,
        onSend: {},
        onImageSend: {_,_ in}
    )
    
}

