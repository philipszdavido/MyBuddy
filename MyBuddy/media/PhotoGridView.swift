//
//  PhotoGridView.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 18/07/2025.
//

import SwiftUI
import Photos

struct PhotoGridView: View {
    @StateObject private var viewModel = PhotoLibraryViewModel()
    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(viewModel.images, id: \.self) { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipped()
                        .cornerRadius(8)
                }

                ForEach(viewModel.videoAssets, id: \.self) { asset in
                    VideoThumbnailView(asset: asset)
                }
            }
            .padding()
        }
    }
}


#Preview {
    PhotoGridView()
}

struct PhotoHorizontalView: View {
    
    @StateObject private var viewModel = PhotoLibraryViewModel()
    @Binding var selectedImage: UIImage?
    
    var body: some View {
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.images, id: \.self) { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipped()
                        .cornerRadius(8)
                        .onTapGesture {
                            selectedImage = image
                        }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 70)

    }
}

struct VideoThumbnailView: View {
    let asset: PHAsset

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipped()
                    .overlay(
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 24))
                            .padding(),
                        alignment: .bottomTrailing
                    )
                    .cornerRadius(8)
            } else {
                Color.gray
                    .frame(width: 100, height: 100)
                    .cornerRadius(8)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    func loadThumbnail() {
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat

        imageManager.requestImage(for: asset, targetSize: CGSize(width: 200, height: 200), contentMode: .aspectFill, options: options) { image, _ in
            if let image = image {
                self.thumbnail = image
            }
        }
    }
}

class PhotoLibraryViewModel: ObservableObject {
    @Published var images: [UIImage] = []
    @Published var videoAssets: [PHAsset] = []

    init() {
        checkAuthorization()
    }

    func checkAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            fetchAssets()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    DispatchQueue.main.async {
                        self.fetchAssets()
                    }
                }
            }
        default:
            break
        }
    }

    func fetchAssets() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        let imageManager = PHImageManager.default()

        allAssets.enumerateObjects { asset, _, _ in
            if asset.mediaType == .image {
                let targetSize = CGSize(width: 200, height: 200)
                let options = PHImageRequestOptions()
                options.isSynchronous = false
                options.deliveryMode = .highQualityFormat

                imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
                    if let img = image {
                        DispatchQueue.main.async {
                            self.images.append(img)
                        }
                    }
                }
            } else if asset.mediaType == .video {
                DispatchQueue.main.async {
                    self.videoAssets.append(asset)
                }
            }
        }
    }
}
