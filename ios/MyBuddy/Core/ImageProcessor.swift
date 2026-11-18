//
//  ImageProcessor.swift
//  MyBuddy
//
//  Resize + compress before upload; thumbnail decoding for display. Never upscales.
//

import UIKit
import ImageIO

struct ProcessedImage: Sendable {
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

enum ImageProcessor {
    static let chatMaxDimension: CGFloat = 1600
    static let avatarMaxDimension: CGFloat = 512
    static let jpegQuality: CGFloat = 0.8

    /// Off-main-actor wrapper.
    static func prepare(_ image: UIImage, maxDimension: CGFloat) async -> ProcessedImage? {
        await Task.detached(priority: .userInitiated) {
            prepareSync(image, maxDimension: maxDimension)
        }.value
    }

    static func prepareSync(_ image: UIImage, maxDimension: CGFloat) -> ProcessedImage? {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixelSize.width, pixelSize.height)
        guard longest > 0 else { return nil }
        let ratio = min(1, maxDimension / longest)
        let target = CGSize(width: max(1, (pixelSize.width * ratio).rounded()),
                            height: max(1, (pixelSize.height * ratio).rounded()))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1          // target is in pixels
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let data = renderer.jpegData(withCompressionQuality: jpegQuality) { _ in
            image.draw(in: CGRect(origin: .zero, size: target))   // applies orientation
        }
        return ProcessedImage(data: data, pixelWidth: Int(target.width), pixelHeight: Int(target.height))
    }

    /// Decodes at most `maxPixel` on the long edge without inflating the full-size bitmap.
    static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func downsampledJPEG(from data: Data, maxPixel: CGFloat) -> Data? {
        downsample(data: data, maxPixel: maxPixel)?.jpegData(compressionQuality: jpegQuality)
    }
}

/// Bounded in-memory cache of decoded thumbnails (evicts under memory pressure).
final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 150
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func image(key: String, data: Data, maxPixel: CGFloat) -> UIImage? {
        let cacheKey = "\(key)-\(data.count)-\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: cacheKey) { return hit }
        guard let decoded = ImageProcessor.downsample(data: data, maxPixel: maxPixel) else { return nil }
        cache.setObject(decoded, forKey: cacheKey, cost: Int(decoded.size.width * decoded.size.height * 4 * decoded.scale * decoded.scale))
        return decoded
    }
}
