import ImageIO
import UIKit

/// Decodes an image file directly to a target display size using ImageIO, so the full-resolution
/// pixel buffer is never materialized in memory. Callers pass the target size explicitly; the loader
/// is a plain (non-isolated) enum so it can be invoked from background tasks.
enum DownsamplingImageLoader {
    /// Loads `url` downsampled so its largest dimension is at most `maxPixelSize` pixels.
    /// Returns `nil` if the file is missing or cannot be decoded.
    static func load(contentsOf url: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Loads `url` downsampled to fit `pointSize` at the given `scale` (target pixels = max side × scale).
    static func load(contentsOf url: URL, pointSize: CGSize, scale: CGFloat) -> UIImage? {
        let maxPixelSize = Int((max(pointSize.width, pointSize.height) * scale).rounded())
        return load(contentsOf: url, maxPixelSize: maxPixelSize)
    }
}
