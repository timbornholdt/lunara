import Foundation
import UIKit

final class ArtworkMemoryCache {
    private let cache = NSCache<NSString, UIImage>()

    func image(for key: ArtworkCacheKey) -> UIImage? {
        cache.object(forKey: key.cacheKeyString as NSString)
    }

    func store(_ image: UIImage, for key: ArtworkCacheKey) {
        cache.setObject(image, forKey: key.cacheKeyString as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
