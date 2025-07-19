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
    
    @State var isPresented = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                
                Button {
                    
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
            MediaChatSheetView()
                .presentationDetents([.fraction(0.8), .large])
                .presentationDragIndicator(.visible)
            
        }
        
        
    }
}

#Preview {
    
    @Previewable @State var text = ""
    
    return ChatInputBar(
        text: $text,
        colorScheme: ColorScheme.dark,
        onSend: {}
    )
    
}

struct CapsuleTextEditor: View {
    @Binding var text: String
    var colorScheme: ColorScheme

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text("Message")
                    .foregroundColor(.gray)
                    .padding(.leading, 20)
                    .padding(.vertical, 10)
            }

            TextEditor(text: $text)
                .padding(10)
                .frame(height: 60) // Enough for ~2 lines
                .background(colorScheme == .light ? Color(white: 0.9) : Color(white: 0.2))
                .foregroundColor(colorScheme == .light ? .black : .white)
                .clipShape(Capsule())
                .scrollContentBackground(.hidden) // Remove default bg
                .lineLimit(2)
                .overlay(
                    Capsule()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                )                
                .padding(.horizontal, 1) // Fine-tune spacing
        }
        .frame(minHeight: 60, maxHeight: 60) // Fixed height to restrict to 2 lines
    }
}

struct CapsuleTextEditorV2: View {
    @Binding var text: String
    var colorScheme: ColorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if text.isEmpty {
                Text("Message")
                    .foregroundColor(.gray)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
            }

            TextEditor(text: $text)
                .padding(10)
                .frame(height: 60)
                .background(colorScheme == .light ? Color(white: 0.9) : Color(white: 0.2))
                .foregroundColor(colorScheme == .light ? .black : .white)
                .clipShape(Capsule())
                .scrollContentBackground(.hidden)
                .overlay(
                    Capsule()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 1)
        .frame(minHeight: 60, maxHeight: 60)
    }
}

struct TextFieldInput: View {
    
    @Binding var text: String
    var colorScheme: ColorScheme

    var body: some View {
        TextField("Message", text: $text)
            .padding(10)
            .background(colorScheme == .light ? Color(white: 0.9) : Color(white: 0.2))
            .foregroundStyle(colorScheme == .light ? .black : .white)
            .clipShape(Capsule())
            .multilineTextAlignment(.leading)
        
    }
}
