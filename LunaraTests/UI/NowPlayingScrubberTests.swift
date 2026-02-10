import Foundation
import Testing
@testable import Lunara

@MainActor
struct NowPlayingScrubberTests {
    @Test func seekIsSkippedWithinTolerance() {
        let shouldSeek = NowPlayingSeekDecision.shouldSeek(
            currentTime: 120,
            targetTime: 124.9,
            tolerance: 5
        )

        #expect(shouldSeek == false)
    }

    @Test func seekHappensOutsideTolerance() {
        let shouldSeek = NowPlayingSeekDecision.shouldSeek(
            currentTime: 120,
            targetTime: 130.1,
            tolerance: 5
        )

        #expect(shouldSeek == true)
    }
}
