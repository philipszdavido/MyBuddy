//
//  DraggableImageView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 23/07/2025.
//

import SwiftUI

struct DraggableImageView: View {
    @Binding var imageOverlay: ImageOverlay
    @GestureState private var dragOffset = CGSize.zero

    var body: some View {
        Image(uiImage: imageOverlay.image)
            .resizable()
            .frame(width: imageOverlay.size.width, height: imageOverlay.size.height)
            .position(x: imageOverlay.position.x + dragOffset.width,
                      y: imageOverlay.position.y + dragOffset.height)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        imageOverlay.position.x += value.translation.width
                        imageOverlay.position.y += value.translation.height
                    }
            )
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 20, height: 20)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newSize = CGSize(
                                    width: max(30, imageOverlay.size.width + value.translation.width),
                                    height: max(30, imageOverlay.size.height + value.translation.height)
                                )
                                imageOverlay.size = newSize
                            }
                    )
                    .padding(6)
            }
    }
}

//#Preview {
//    DraggableImageView()
//}
