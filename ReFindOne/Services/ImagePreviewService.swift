import UIKit
import ImageIO

actor ImagePreviewService {
    static let shared = ImagePreviewService()
    private let cache = NSCache<NSURL, UIImage>()

    init() { cache.totalCostLimit = 24 * 1024 * 1024 }

    func thumbnail(for url: URL) -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 700,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let thumbnail = UIImage(cgImage: image)
        cache.setObject(thumbnail, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        return thumbnail
    }
}
