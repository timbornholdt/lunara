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
        // 10 samples: body level ~0.5, last 2 are well below threshold (0.5 * 0.4 = 0.2)
        let levels: [Float] = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.1, 0.05]
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: levels, trackDuration: 100)
        // fadeStartIndex = 8, fadeFraction = 2/10 = 0.2, computed = 20, capped at 12
        #expect(duration == 12)
    }

    @Test
    func loudnessAware_shortFade_clampedToMin() {
        // Only last sample is quiet
        let levels: [Float] = Array(repeating: 0.5, count: 99) + [0.1]
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: levels, trackDuration: 100)
        // fadeFraction = 1/100 = 0.01, computedDuration = 1.0, clamped to 2
        #expect(duration == 2)
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

    @Test
    func hardEnding_usesDefault() {
        // All samples at body level through the end — no fade detected
        let levels: [Float] = Array(repeating: 0.6, count: 128)
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: levels, trackDuration: 240)
        #expect(duration == 3)
    }

    @Test
    func naturalFadeOut_detectsOnset() {
        // 128 samples: 112 at body level, then 16-sample gradual decline
        var levels: [Float] = Array(repeating: 0.7, count: 112)
        for i in 0..<16 {
            levels.append(0.7 * Float(16 - i) / 16.0 * 0.3) // declines from ~0.21 to ~0.013
        }
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: levels, trackDuration: 256)
        // Fade region is 16/128 = 0.125, computed = 32s, capped to 12
        #expect(duration == 12)
    }

    @Test
    func quietTrack_usesRelativeThreshold() {
        // Low overall loudness (body ~0.12) with a proportional fade at the end
        var levels: [Float] = Array(repeating: 0.12, count: 100)
        // Last 15 samples fade to near zero (below threshold of 0.12 * 0.4 = 0.048)
        for i in 0..<15 {
            levels.append(0.04 * Float(15 - i) / 15.0)
        }
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: levels, trackDuration: 230)
        // fadeStartIndex = 100, fadeFraction = 15/115, computed ≈ 30, capped to 12
        #expect(duration == 12)
    }

    @Test
    func nonMonotonicQuietSection_usesDefault() {
        // Quiet section that goes back up (e.g. hidden track after silence)
        var levels: [Float] = Array(repeating: 0.6, count: 80)
        // 20 samples of silence
        levels.append(contentsOf: Array(repeating: Float(0.02), count: 20))
        // Then 28 samples of music again
        levels.append(contentsOf: Array(repeating: Float(0.5), count: 28))
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: levels, trackDuration: 300)
        // The fade region (from last >= threshold onwards) would be the last ~28 samples
        // but they're not decreasing, so validation fails → default
        #expect(duration == 3)
    }
}
