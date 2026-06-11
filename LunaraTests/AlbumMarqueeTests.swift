import Foundation
import SwiftUI
import Testing
@testable import Lunara

/// Lunara-1mu: the marquee's wrap math is pure and tested directly.
@Suite
struct AlbumMarqueeTests {
    @Test
    func marqueeOffset_startsAtZeroAndSlidesLeft() {
        #expect(AlbumMarquee.marqueeOffset(elapsed: 0, speed: 14, contentWidth: 700) == 0)
        let early = AlbumMarquee.marqueeOffset(elapsed: 10, speed: 14, contentWidth: 700)
        #expect(early == -140)
    }

    @Test
    func marqueeOffset_wrapsSeamlesslyAtContentWidth() {
        // 700pt of content at 14pt/s wraps every 50s.
        let justBefore = AlbumMarquee.marqueeOffset(elapsed: 49.999, speed: 14, contentWidth: 700)
        let atWrap = AlbumMarquee.marqueeOffset(elapsed: 50, speed: 14, contentWidth: 700)
        let justAfter = AlbumMarquee.marqueeOffset(elapsed: 50.5, speed: 14, contentWidth: 700)
        #expect(justBefore < -699)
        #expect(atWrap == 0)
        #expect(justAfter == -7)
    }

    @Test
    func marqueeOffset_zeroOrNegativeWidthIsSafe() {
        #expect(AlbumMarquee.marqueeOffset(elapsed: 100, speed: 14, contentWidth: 0) == 0)
        #expect(AlbumMarquee.marqueeOffset(elapsed: 100, speed: 14, contentWidth: -5) == 0)
    }

    @Test
    func paddedURLs_repeatShortCollectionsToFillTheRow() {
        let url = URL(string: "file:///a.jpg")
        let padded = AlbumMarquee.paddedURLs([url, nil], minimumCount: 8)
        #expect(padded.count == 8)
        #expect(padded[0] == url)
        #expect(padded[2] == url) // repeats wrap around the input
    }

    /// Lunara-910: the duplicated tile strip must NOT report its full width as
    /// the marquee's ideal size — that leaked ~1300pt into the ScrollView and
    /// pushed the whole collection page offscreen. ImageRenderer renders at the
    /// view's ideal size, so it's a direct probe.
    @Test
    @MainActor
    func marquee_idealWidthStaysNearScreenWidth() {
        // No outer frame: ImageRenderer sizes to the view's IDEAL size, which is
        // exactly what leaked (the strip's ~1300pt) in the broken layout.
        let marquee = AlbumMarquee(
            thumbnailURLs: Array(repeating: nil, count: 12),
            height: 150
        )

        let renderer = ImageRenderer(content: marquee)
        let size = renderer.uiImage?.size ?? .zero

        #expect(size.width <= 400)
        #expect(size.height <= 160)
    }

    @Test
    func paddedURLs_emptyInputYieldsPlaceholders() {
        let padded = AlbumMarquee.paddedURLs([], minimumCount: 8)
        #expect(padded.count == 8)
        #expect(padded.allSatisfy { $0 == nil })
    }
}
