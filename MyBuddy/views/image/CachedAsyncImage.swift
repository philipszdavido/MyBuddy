//
//  CachedAsyncImage.swift
//  MyBuddy
//
//  Created by Chidume Nnamdi on 26/07/2025.
//

import SwiftUI

class ImageCache {
    static let shared = ImageCache()

    let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ImageCache", isDirectory: true)

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func getCachedImage(for url: URL) -> UIImage? {
        let fileURL = folder.appendingPathComponent(url.lastPathComponent)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    func cache(image: UIImage, for url: URL) {
        let fileURL = folder.appendingPathComponent(url.lastPathComponent)
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: fileURL)
    }
}

struct CachedAsyncImage: View {
    let url: URL?
    let width: Int
    let height: Int

    @State private var uiImage: UIImage?

    var body: some View {
        
        Group {
            if let image = uiImage {
                Image(uiImage: image)
                    .resizable()
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .onAppear {
                        loadImage()
                    }
            }
        }
        .scaledToFill()
        .clipShape(Circle())
        .frame(width: CGFloat(width), height: CGFloat(height))
        .onAppear {
        }
        
    }

    func loadImage() {
        guard let url else { return }
        
        print("loadImage", url)

        // Check cache first
        if let cached = ImageCache.shared.getCachedImage(for: url) {
            self.uiImage = cached
            return
        }

        // Fetch and cache
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            ImageCache.shared.cache(image: image, for: url)
            DispatchQueue.main.async {
                self.uiImage = image
            }
        }.resume()
    }
}


#Preview {
    CachedAsyncImage(
        url: URL(
            string: "https://res.cloudinary.com/dwbggi96z/image/upload/v1753476178/chat_images/piwo39uqyfekrbbtvmpl.jpg"
        )!,
        width: 70,
        height: 70
    )
}
