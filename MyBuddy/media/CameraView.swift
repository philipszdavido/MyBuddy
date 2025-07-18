//
//  CustomCameraView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 18/07/2025.
//

import SwiftUI
import AVFoundation
import PhotosUI
import Photos

struct CameraView: View {

    @Environment(\.colorScheme) var colorScheme;
    @State private var selectedMode: CameraMode = .photo
    @State private var showingPicker = false
    @StateObject private var cameraService = CameraService()
    @Environment(\.dismiss) var dismiss
    
    @Binding var selectedImage: UIImage?
    
    var body: some View {
        
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
                    Button(action: {}) {
                        Image(systemName: "circle.lefthalf.fill")
                    }
                    Button(action: {}) {
                        Image(systemName: "bolt.badge.a")
                    }
                }
                .padding(.trailing)
            }
            .padding(.horizontal)
            .padding(.top)
            
            Spacer()
            
            VStack {
                
                // Media Strip
                PhotoHorizontalView(selectedImage: $selectedImage)
                
                // Capture Controls
                HStack {
                    Button(action: {
                        launchPhotoPicker()
                    }) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        cameraAction()
                    }) {
                        
                        if selectedMode == .video && cameraService.isRecording {
                            
                            Circle()
                                .fill(Color.red)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .padding(8)
                            
                        } else {
                            
                            Circle()
                                .fill(.gray.opacity(0.3))
                                .strokeBorder(.white, lineWidth: 4)
                                .frame(width: 80, height: 80)

                        }

                    }
                    
                    Spacer()
                    
                    Button(action: {
                        cameraService.toggleCamera()
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title2)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top)
                .padding(.bottom, 30)
                
                // Mode Selector
                HStack(spacing: 30) {
                    ForEach(CameraMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                            .foregroundStyle(
                                mode == selectedMode ? .yellow : (colorScheme == .dark ? .white : .black))
                            .onTapGesture {
                                selectedMode = mode
                            }
                    }
                }
                .font(.footnote.bold())
                .padding(.bottom, 50)
            }
            
        }
        .background(
            CameraPreviewView(session: cameraService.session)
        )
        .ignoresSafeArea()
        .sheet(isPresented: $showingPicker) {
            PhotoPickerView(selectedImage: $selectedImage)
        }
        .onReceive(cameraService.$capturedImage) { image in
            if let image = image {
                selectedImage = image
            }
        }
    }
    
    func launchPhotoPicker() {
        showingPicker = true
    }
        
    func cameraAction() {
        switch selectedMode {
        case .photo:
            cameraService.capturePhoto()
        case .video:
            if cameraService.isRecording {
                cameraService.stopVideoRecording()
            } else {
                cameraService.startVideoRecording()
            }
        }
    }
    
}

enum CameraMode: String, CaseIterable {
    case video = "VIDEO"
    case photo = "PHOTO"
    // case videoNote = "VIDEO NOTE"
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }

        func configure(session: AVCaptureSession) {
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
        }
    }

    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.configure(session: session)
        return view
    }

    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        uiView.configure(session: session)
    }
}

class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    
    // MARK: - Published Properties
    @Published var session = AVCaptureSession()
    @Published var capturedImage: UIImage?
    @Published var isRecording = false

    // MARK: - Private Properties
    private var currentPosition: AVCaptureDevice.Position = .back
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    
    override init() {
        super.init()
        configureSession()
    }
    
    // MARK: - Session Setup
    func configureSession() {
        session.beginConfiguration()
        
        // Remove all existing inputs/outputs
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        // Add camera input
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)

        // Add photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        // Add movie output
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()

        if !session.isRunning {
            session.startRunning()
        }
    }

    // MARK: - Camera Toggle
    func toggleCamera() {
        currentPosition = (currentPosition == .back) ? .front : .back
        configureSession()
    }

    // MARK: - Photo Capture
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            return
        }

        DispatchQueue.main.async {
            self.capturedImage = image
        }

        // Optional: Save to gallery
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }
    }

    // MARK: - Video Recording
    func startVideoRecording() {
        guard !movieOutput.isRecording else { return }

        let outputPath = NSTemporaryDirectory() + UUID().uuidString + ".mov"
        let outputURL = URL(fileURLWithPath: outputPath)

        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        isRecording = true
    }

    func stopVideoRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        isRecording = false

        // Optional: Save video to gallery
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
            }
        }
    }
}

struct PhotoPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView

        init(parent: PhotoPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider else { return }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        DispatchQueue.main.async {
                            self.parent.selectedImage = image
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    CameraView(selectedImage: .constant(UIImage(systemName: "")))
}

