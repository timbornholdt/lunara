import Foundation
import Testing
@testable import Lunara

struct ArtworkCacheKeyTests {
    @Test func keyStringIncludesRatingKeyArtworkPathAndSize() {
        let key = ArtworkCacheKey(ratingKey: "123", artworkPath: "/library/metadata/10/thumb", size: .grid)

        #expect(key.cacheKeyString.contains("123"))
        #expect(key.cacheKeyString.contains("/library/metadata/10/thumb"))
        #expect(key.cacheKeyString.contains(String(ArtworkSize.grid.maxPixelSize)))
    }

    @Test func fileNameChangesWhenSizeChanges() {
        let gridKey = ArtworkCacheKey(ratingKey: "123", artworkPath: "/library/metadata/10/thumb", size: .grid)
        let detailKey = ArtworkCacheKey(ratingKey: "123", artworkPath: "/library/metadata/10/thumb", size: .detail)

        #expect(gridKey.fileName != detailKey.fileName)
    }
}
