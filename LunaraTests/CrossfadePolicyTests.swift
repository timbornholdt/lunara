import Foundation
import Testing
@testable import Lunara

struct CrossfadePolicyTests {
    @Test
    func consecutiveTracks_returnsGapless() {
        let result = CrossfadePolicy.transition(
            currentAlbumID: "album-1",
            currentTrackNumber: 3,
            nextAlbumID: "album-1",
            nextTrackNumber: 4,
            currentTrackDuration: 240,
            loudnessLevels: nil
        )
        #expect(result == .gapless)
    }

    @Test
    func differentAlbums_returnsCrossfade() {
        let result = CrossfadePolicy.transition(
            currentAlbumID: "album-1",
            currentTrackNumber: 3,
            nextAlbumID: "album-2",
            nextTrackNumber: 1,
            currentTrackDuration: 240,
            loudnessLevels: nil
        )
        guard case .crossfade(let startTime, let duration) = result else {
            Issue.record("Expected crossfade")
            return
        }
        #expect(duration == 3)
        #expect(startTime == 237)
    }

    @Test
    func sameAlbumNonConsecutive_returnsCrossfade() {
        let result = CrossfadePolicy.transition(
            currentAlbumID: "album-1",
            currentTrackNumber: 1,
            nextAlbumID: "album-1",
            nextTrackNumber: 5,
            currentTrackDuration: 200,
            loudnessLevels: nil
        )
        guard case .crossfade = result else {
            Issue.record("Expected crossfade")
            return
        }
    }

    @Test
    func emptyAlbumID_returnsCrossfade() {
        let result = CrossfadePolicy.transition(
            currentAlbumID: "",
            currentTrackNumber: 1,
            nextAlbumID: "",
            nextTrackNumber: 2,
            currentTrackDuration: 200,
            loudnessLevels: nil
        )
        guard case .crossfade = result else {
            Issue.record("Expected crossfade for empty album IDs")
            return
        }
    }

    @Test
    func loudnessAware_computesDurationFromTrailingQuietness() {
        // 10 samples, last 2 are below threshold (0.15)
        var levels: [Float] = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.1, 0.05]
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: levels, trackDuration: 100)
        // fadeStartIndex = 8 (last >= threshold is index 7, so fadeStartIndex = 8)
        // fadeFraction = (10 - 8) / 10 = 0.2
        // computedDuration = 0.2 * 100 = 20, capped at 8
        #expect(duration == 8)
    }

    @Test
    func loudnessAware_shortFade_clampedToMin() {
        // Only last sample is quiet
        var levels: [Float] = Array(repeating: 0.5, count: 99) + [0.1]
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: levels, trackDuration: 100)
        // fadeFraction = 1/100 = 0.01, computedDuration = 1.0, clamped to 1
        #expect(duration == 1)
    }

    @Test
    func loudnessAware_noQuietSection_returnsDefault() {
        let levels: [Float] = Array(repeating: 0.5, count: 100)
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: levels, trackDuration: 200)
        #expect(duration == 3)
    }

    @Test
    func noLoudnessData_returnsDefault() {
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: nil, trackDuration: 200)
        #expect(duration == 3)
    }

    @Test
    func emptyLoudnessArray_returnsDefault() {
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: [], trackDuration: 200)
        #expect(duration == 3)
    }
}
