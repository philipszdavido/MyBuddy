//
//  ResizableImageView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 23/07/2025.
//

import SwiftUI

struct ResizableImageView: View {
    @Binding var image: UIImage
    @State private var size: CGSize = CGSize(width: 300, height: 300)
    @State private var dragOffset = CGSize.zero
    var selectedTool: Tool?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottomTrailing) {
                if selectedTool == .resize {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 20, height: 20)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newWidth = max(50, size.width + value.translation.width)
                                    let newHeight = max(50, size.height + value.translation.height)
                                    size = CGSize(width: newWidth, height: newHeight)
                                }
                        )
                        .padding(8)
                }
            }
    }
}

//#Preview {
//    ResizableImageView()
//}
