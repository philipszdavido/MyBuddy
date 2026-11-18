//
//  MediaView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 18/07/2025.
//

import SwiftUI
import AVFoundation

struct MediaView: View {
    
    @State private var showPicker = false
    @State private var pickerType: MediaPickerType = .cameraPhoto
    @State private var selectedImage: UIImage?
    @State private var selectedVideoURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Button("📷 Take Photo") {
                pickerType = .cameraPhoto
                showPicker = true
            }

            Button("🎥 Record Video") {
                pickerType = .cameraVideo
                showPicker = true
            }

            Button("🖼️ Pick Image") {
                pickerType = .photoLibraryImage
                showPicker = true
            }

            Button("🎞️ Pick Video") {
                pickerType = .photoLibraryVideo
                showPicker = true
            }

            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
            }

            if let videoURL = selectedVideoURL {
                Text("📹 Selected video: \(videoURL.lastPathComponent)")
            }
        }
        .sheet(isPresented: $showPicker) {
            MediaPicker(
                type: pickerType,
                onImagePicked: { image in
                    selectedImage = image
                },
                onVideoPicked: { url in
                    selectedVideoURL = url
                }
            )
        }
    }
}

#Preview {
    MediaView()
}
