//
//  MediaPicker.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 18/07/2025.
//

import Foundation
import SwiftUI
import PhotosUI
import AVFoundation

enum MediaPickerType {
    case cameraPhoto
    case cameraVideo
    case photoLibraryImage
    case photoLibraryVideo
}

struct MediaPicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode

    let type: MediaPickerType
    let onImagePicked: ((UIImage) -> Void)?
    let onVideoPicked: ((URL) -> Void)?

    func makeUIViewController(context: Context) -> UIViewController {
        switch type {
        case .photoLibraryImage, .photoLibraryVideo:
            var config = PHPickerConfiguration()
            config.selectionLimit = 1
            config.filter = type == .photoLibraryImage ? .images : .videos
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        case .cameraPhoto, .cameraVideo:
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.sourceType = .camera
            picker.mediaTypes = [type == .cameraPhoto ? "public.image" : "public.movie"]
            picker.videoQuality = .typeHigh
            picker.cameraCaptureMode = type == .cameraPhoto ? .photo : .video
            return picker
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate, PHPickerViewControllerDelegate {
        let parent: MediaPicker

        init(_ parent: MediaPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()

            guard let item = results.first else { return }

            if item.itemProvider.canLoadObject(ofClass: UIImage.self) {
                item.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                    if let uiImage = image as? UIImage {
                        DispatchQueue.main.async {
                            self.parent.onImagePicked?(uiImage)
                        }
                    }
                }
            } else if item.itemProvider.hasItemConformingToTypeIdentifier("public.movie") {
                item.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.parent.onVideoPicked?(url)
                        }
                    }
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            parent.presentationMode.wrappedValue.dismiss()

            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked?(image)
            }

            if let videoURL = info[.mediaURL] as? URL {
                parent.onVideoPicked?(videoURL)
            }
        }
    }

}

