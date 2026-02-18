import CoreFoundation
import Testing
@testable import Lunara

struct AlbumDetailLayoutTests {
    @Test
    func layoutConstants_keepHeaderNearTopWithConsistentMargins() {
        #expect(AlbumDetailLayout.horizontalPadding == 16)
        #expect(AlbumDetailLayout.topContentPadding == 8)
        #expect(AlbumDetailLayout.sectionSpacing == 20)
    }

    @Test
    func backButtonInsets_matchTopSafeAreaDesign() {
        #expect(AlbumDetailLayout.backButtonInsetTop == 6)
        #expect(AlbumDetailLayout.backButtonInsetBottom == 8)
    }
}
