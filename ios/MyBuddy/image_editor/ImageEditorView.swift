//
//  ImageEditorView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 23/07/2025.
//

import SwiftUI

struct ImageEditorView: View {
        
    @State private var baseImage: UIImage = UIImage(named: "bg")!
    // Replace with your image
    @State private var overlayTexts: [TextOverlay] = []
    @State private var overlayImages: [ImageOverlay] = []
    @State private var selectedTool: Tool? = nil
    
    var body: some View {
        VStack {
            // Toolbar
            HStack {
                Button("Resize") { selectedTool = .resize }
                Button("Text") { selectedTool = .text }
                Button("Add Image") {
                    selectedTool = .addImage
                    overlayImages.append(ImageOverlay())
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            GeometryReader { geo in
                ZStack {
                    // Base image with resizable logic
                    ResizableImageView(image: $baseImage, selectedTool: selectedTool)
                        .gesture(
                            TapGesture()
                                .onEnded {
                                    if selectedTool == .text {
                                        let newOverlay = TextOverlay(position: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                                        overlayTexts.append(newOverlay)
                                    }
                                }
                        )

                    // Text overlays
                    ForEach(overlayTexts.indices, id: \.self) { i in
                        DraggableTextView(textOverlay: $overlayTexts[i])
                    }

                    // Image overlays
                    ForEach(overlayImages.indices, id: \.self) { i in
                        DraggableImageView(imageOverlay: $overlayImages[i])
                    }
                }
                .clipped()
                .background(Color.gray.opacity(0.2))
            }
        }
    }
}

enum Tool {
    case resize, text, addImage
}

struct TextOverlay {
    var text: String = "Type here"
    var position: CGPoint
    var fontSize: CGFloat = 18
}

struct ImageOverlay {
    var image: UIImage = UIImage(systemName: "star.fill")! // Replace with your overlay image
    var position: CGPoint = CGPoint(x: 150, y: 150)
    var size: CGSize = CGSize(width: 100, height: 100)
}

#Preview {
    ImageEditorView()
}
