import Foundation
import CryptoKit

struct ArtworkCacheKey: Hashable, Codable, Sendable {
    let ratingKey: String
    let artworkPath: String
    let size: ArtworkSize

    var cacheKeyString: String {
        "\(ratingKey)|\(artworkPath)|\(size.maxPixelSize)"
    }

    var fileName: String {
        let hash = SHA256.hash(data: Data(cacheKeyString.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined() + ".png"
    }
}
