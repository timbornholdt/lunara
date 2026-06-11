import SwiftUI
import UIKit

/// Renders a LOCAL artwork file decoded at display size via DownsamplingImageLoader,
/// replacing AsyncImage in grid/list cells. AsyncImage decodes the full-resolution
/// pixel buffer (and routes even file URLs through URLSession); this decodes a
/// bounded thumbnail off the main actor instead (Lunara-gxq).
struct DownsampledThumbnail: View {
    let url: URL
    /// Largest pixel dimension of the decoded image — display points × screen scale.
    let maxPixelSize: Int

    @State private var image: UIImage?

    init(url: URL, maxPixelSize: Int) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        // Cache hits render on the first frame — no placeholder flash when
        // scrolling back over cells already decoded this session (Lunara-inq).
        _image = State(initialValue: Self.cachedImage(url: url, maxPixelSize: maxPixelSize))
    }

    var body: some View {
        // No inner flexible frame: inside a SquareArtworkView the image must not
        // drive the container's layout — fill is contained by the caller's
        // square + clip (Lunara-jou).
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Static placeholder: a spinner per cell makes fast grid
                // scrolls animate dozens of ProgressViews at once (Lunara-inq).
                Color(.secondarySystemFill)
            }
        }
        .task(id: url) {
            image = await Self.decode(url: url, maxPixelSize: maxPixelSize)
        }
    }

    /// Decoded-thumbnail memory cache so re-scrolling never re-decodes from
    /// disk (Lunara-inq). Keyed by path+size; NSCache evicts under pressure.
    private static let decodeCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    private static func cacheKey(url: URL, maxPixelSize: Int) -> NSString {
        "\(url.path)#\(maxPixelSize)" as NSString
    }

    static func cachedImage(url: URL, maxPixelSize: Int) -> UIImage? {
        decodeCache.object(forKey: cacheKey(url: url, maxPixelSize: maxPixelSize))
    }

    /// Decodes off the main actor; nil when the file is missing or undecodable.
    static func decode(url: URL, maxPixelSize: Int) async -> UIImage? {
        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
        if let cached = decodeCache.object(forKey: key) {
            return cached
        }
        let image = await Task.detached {
            DownsamplingImageLoader.load(contentsOf: url, maxPixelSize: maxPixelSize)
        }.value
        if let image {
            decodeCache.setObject(image, forKey: key)
        }
        return image
    }
}
