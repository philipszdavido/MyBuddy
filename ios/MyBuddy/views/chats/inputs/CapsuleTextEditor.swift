//
//  CapsuleTextEditor.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 23/07/2025.
//

import SwiftUI

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
                //.padding(10)
                //.frame(height: 60)
                // Enough for ~2 lines
                .background(colorScheme == .light ? Color(white: 0.9) : Color(white: 0.2))
                .foregroundColor(colorScheme == .light ? .black : .white)
                .clipShape(Capsule())
                .scrollContentBackground(.hidden)
                // Remove default bg
                .lineLimit(2)
                .overlay(
                    Capsule()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                )
                .padding(.horizontal, 1)
            // Fine-tune spacing
        }
        .frame(minHeight: 30, maxHeight: 30)
        //.frame(minHeight: 60, maxHeight: 60)
        // Fixed height to restrict to 2 lines
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

#Preview {
    CapsuleTextEditorV2(text: .constant("iop"), colorScheme: .light)
}
