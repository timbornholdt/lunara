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
    func loudnessAware_noQuietSection_usesMinimumNotDefault() {
        // Contour says the track ends hot — cut as little of it as possible
        // instead of the blind 3s default (Lunara-2vz).
        let levels: [Float] = Array(repeating: 0.5, count: 100)
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: levels, trackDuration: 200)
        #expect(duration == 2)
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
    func hardEnding_usesMinimum() {
        // All samples at body level through the end — no fade detected, so the
        // fade is as short as allowed rather than chopping 3s of hot audio.
        let levels: [Float] = Array(repeating: 0.6, count: 128)
        let duration = CrossfadePolicy.crossfadeDuration(loudnessLevels: levels, trackDuration: 240)
        #expect(duration == 2)
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
        // but they're not decreasing, so no outro is detected → minimum cut
        #expect(duration == 2)
    }

    // MARK: - Incoming music onset (Lunara-2vz sweet fades)

    /// Outgoing outro of 6s + incoming quiet intro: the overlap stretches so the
    /// incoming's music arrives while the outgoing is still audible.
    @Test
    func quietIntroIncoming_lengthensOverlap() {
        // Outgoing: 100 samples over 60s, last 10 a clean fade → 6s outro.
        var outgoing: [Float] = Array(repeating: 0.6, count: 90)
        for i in 0..<10 {
            outgoing.append(0.15 * Float(10 - i) / 10.0)
        }
        let outroOnly = CrossfadePolicy.crossfadeDuration(loudnessLevels: outgoing, trackDuration: 60)
        #expect(outroOnly == 6)

        // Incoming: first 25% near-silence, then body. 80s track → 20s onset,
        // capped at the 4s max lead.
        var incoming: [Float] = Array(repeating: 0.01, count: 25)
        incoming.append(contentsOf: Array(repeating: 0.5, count: 75))

        let combined = CrossfadePolicy.crossfadeDuration(
            loudnessLevels: outgoing,
            trackDuration: 60,
            nextLoudnessLevels: incoming,
            nextTrackDuration: 80
        )
        #expect(combined == 10) // 6s outro + 4s capped onset lead
    }

    /// An incoming track that starts hot adds no lead.
    @Test
    func hotIncoming_addsNoLead() {
        var outgoing: [Float] = Array(repeating: 0.6, count: 90)
        for i in 0..<10 {
            outgoing.append(0.15 * Float(10 - i) / 10.0)
        }
        let incoming: [Float] = Array(repeating: 0.5, count: 100)

        let duration = CrossfadePolicy.crossfadeDuration(
            loudnessLevels: outgoing,
            trackDuration: 60,
            nextLoudnessLevels: incoming,
            nextTrackDuration: 80
        )
        #expect(duration == 6)
    }

    /// A hot outgoing ending stays a minimal cut even when the incoming has a
    /// quiet intro — never fade body audio early.
    @Test
    func hotEnding_ignoresIncomingLead() {
        let outgoing: [Float] = Array(repeating: 0.6, count: 100)
        var incoming: [Float] = Array(repeating: 0.01, count: 25)
        incoming.append(contentsOf: Array(repeating: 0.5, count: 75))

        let duration = CrossfadePolicy.crossfadeDuration(
            loudnessLevels: outgoing,
            trackDuration: 200,
            nextLoudnessLevels: incoming,
            nextTrackDuration: 80
        )
        #expect(duration == 2)
    }

    /// Without an outgoing contour the default applies, still stretched by the
    /// incoming's onset lead when that contour exists.
    @Test
    func unknownOutgoing_defaultPlusLead() {
        var incoming: [Float] = Array(repeating: 0.01, count: 25)
        incoming.append(contentsOf: Array(repeating: 0.5, count: 75))

        let duration = CrossfadePolicy.crossfadeDuration(
            loudnessLevels: nil,
            trackDuration: 200,
            nextLoudnessLevels: incoming,
            nextTrackDuration: 80
        )
        #expect(duration == 7) // 3s default + 4s capped lead
    }

    /// The whole stack respects the 12s ceiling.
    @Test
    func combinedDuration_clampedToMax() {
        // 25% outro over a 60s track → 15s, already above the cap.
        var outgoing: [Float] = Array(repeating: 0.6, count: 75)
        for i in 0..<25 {
            outgoing.append(0.15 * Float(25 - i) / 25.0)
        }
        var incoming: [Float] = Array(repeating: 0.01, count: 25)
        incoming.append(contentsOf: Array(repeating: 0.5, count: 75))

        let duration = CrossfadePolicy.crossfadeDuration(
            loudnessLevels: outgoing,
            trackDuration: 60,
            nextLoudnessLevels: incoming,
            nextTrackDuration: 80
        )
        #expect(duration == 12)
    }
}
