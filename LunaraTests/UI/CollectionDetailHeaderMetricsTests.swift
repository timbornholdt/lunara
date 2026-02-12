import Foundation
import Testing
@testable import Lunara

struct CollectionDetailHeaderMetricsTests {
    @Test func titleOpacityIsZeroAtTopAndOneWhenCollapsed() {
        #expect(CollectionHeaderMetrics.navTitleOpacity(for: 0) == 0)
        #expect(CollectionHeaderMetrics.navTitleOpacity(for: -500) == 1)
    }

    @Test func headerHeightClampsBetweenMinAndMax() {
        #expect(CollectionHeaderMetrics.headerHeight(for: 40) == CollectionHeaderMetrics.maxHeaderHeight)
        #expect(CollectionHeaderMetrics.headerHeight(for: -1000) == CollectionHeaderMetrics.minHeaderHeight)
    }

    @Test func marqueeOffsetWrapsContinuously() {
        let config = CollectionHeroMarqueeMotion(baseWidth: 500, speed: 50)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let beforeWrap = config.offset(at: Date(timeIntervalSinceReferenceDate: 9.9), startDate: start)
        let atWrap = config.offset(at: Date(timeIntervalSinceReferenceDate: 10.0), startDate: start)
        let afterWrap = config.offset(at: Date(timeIntervalSinceReferenceDate: 10.1), startDate: start)

        #expect(beforeWrap > 0)
        #expect(atWrap == 0)
        #expect(afterWrap > 0)
        #expect(afterWrap < beforeWrap)
    }

    @Test func marqueeOffsetIsZeroWhenBaseWidthIsInvalid() {
        let zeroWidth = CollectionHeroMarqueeMotion(baseWidth: 0, speed: 40)
        let negativeWidth = CollectionHeroMarqueeMotion(baseWidth: -10, speed: 40)
        let now = Date()

        #expect(zeroWidth.offset(at: now, startDate: now) == 0)
        #expect(negativeWidth.offset(at: now, startDate: now) == 0)
    }
}
