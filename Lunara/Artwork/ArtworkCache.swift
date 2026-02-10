import Foundation
import UIKit

final class ArtworkCache {
    private let memoryCache: ArtworkMemoryCache
    private let diskCache: ArtworkDiskCache

    init(memoryCache: ArtworkMemoryCache, diskCache: ArtworkDiskCache) {
        self.memoryCache = memoryCache
        self.diskCache = diskCache
    }

    func image(for key: ArtworkCacheKey) throws -> UIImage? {
        if let cached = memoryCache.image(for: key) {
            return cached
        }
        if let data = try diskCache.imageData(for: key),
           let image = UIImage(data: data) {
            memoryCache.store(image, for: key)
            return image
        }
        return nil
    }

    func imageData(for key: ArtworkCacheKey) throws -> Data? {
        try diskCache.imageData(for: key)
    }

    func store(_ data: Data, for key: ArtworkCacheKey) throws {
        if let image = UIImage(data: data) {
            memoryCache.store(image, for: key)
        }
        try diskCache.store(data, for: key)
    }
}
