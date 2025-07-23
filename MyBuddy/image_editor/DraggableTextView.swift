//
//  DraggableTextView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 23/07/2025.
//

import SwiftUI

struct DraggableTextView: View {
    @Binding var textOverlay: TextOverlay
    @State private var isEditing = false
    @GestureState private var dragOffset = CGSize.zero

    var body: some View {
        TextField("", text: $textOverlay.text)
            .font(.system(size: textOverlay.fontSize))
            .foregroundColor(.black)
            .background(Color.white.opacity(0.5))
            .frame(width: 200)
            .position(x: textOverlay.position.x + dragOffset.width,
                      y: textOverlay.position.y + dragOffset.height)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        textOverlay.position.x += value.translation.width
                        textOverlay.position.y += value.translation.height
                    }
            )
    }
}
//
//#Preview {
//    DraggableTextView()
//}
