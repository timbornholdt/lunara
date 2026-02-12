import Foundation
import UIKit

protocol LockScreenArtworkProviding {
    func resolveArtwork(for request: ArtworkRequest?) async -> UIImage?
}

protocol LockScreenArtworkLoading {
    func loadImage(for key: ArtworkCacheKey, url: URL) async throws -> UIImage
}

extension ArtworkLoader: LockScreenArtworkLoading {}

final class LockScreenArtworkProvider: LockScreenArtworkProviding {
    private let loader: LockScreenArtworkLoading
    private var cache: [String: UIImage] = [:]

    init(loader: LockScreenArtworkLoading = ArtworkLoader.shared) {
        self.loader = loader
    }

    func resolveArtwork(for request: ArtworkRequest?) async -> UIImage? {
        guard let request else { return nil }
        let cacheKey = request.key.cacheKeyString
        if let cached = cache[cacheKey] {
            return cached
        }
        guard let image = try? await loader.loadImage(for: request.key, url: request.url) else {
            return nil
        }
        cache[cacheKey] = image
        return image
    }
}
