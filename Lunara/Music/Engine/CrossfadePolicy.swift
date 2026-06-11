import Foundation

enum TransitionStyle: Equatable, Sendable {
    case gapless
    case crossfade(startTime: TimeInterval, duration: TimeInterval)
}

struct CrossfadePolicy: Sendable {
    static let defaultCrossfadeDuration: TimeInterval = 3
    static let minCrossfadeDuration: TimeInterval = 2
    static let maxCrossfadeDuration: TimeInterval = 12
    static let bodyLevelFraction: Float = 0.40
    /// Cap on how much a quiet incoming intro may stretch the overlap. Bounds
    /// how far before its outro the outgoing track starts fading (Lunara-2vz).
    static let maxOnsetLeadSeconds: TimeInterval = 4

    static func transition(
        currentAlbumID: String,
        currentTrackNumber: Int,
        nextAlbumID: String,
        nextTrackNumber: Int,
        currentTrackDuration: TimeInterval,
        loudnessLevels: [Float]?,
        nextLoudnessLevels: [Float]? = nil,
        nextTrackDuration: TimeInterval? = nil
    ) -> TransitionStyle {
        if isConsecutive(
            currentAlbumID: currentAlbumID,
            currentTrackNumber: currentTrackNumber,
            nextAlbumID: nextAlbumID,
            nextTrackNumber: nextTrackNumber
        ) {
            return .gapless
        }

        let duration = crossfadeDuration(
            loudnessLevels: loudnessLevels,
            trackDuration: currentTrackDuration,
            nextLoudnessLevels: nextLoudnessLevels,
            nextTrackDuration: nextTrackDuration
        )
        let startTime = max(0, currentTrackDuration - duration)
        return .crossfade(startTime: startTime, duration: duration)
    }

    static func isConsecutive(
        currentAlbumID: String,
        currentTrackNumber: Int,
        nextAlbumID: String,
        nextTrackNumber: Int
    ) -> Bool {
        guard !currentAlbumID.isEmpty, !nextAlbumID.isEmpty else { return false }
        return currentAlbumID == nextAlbumID && nextTrackNumber == currentTrackNumber + 1
    }

    /// Sweet-fade duration (Lunara-2vz). Both contour analyses use only
    /// WITHIN-TRACK relative measures — Plex waveform levels may be normalized
    /// per track, so absolute levels are never compared across tracks.
    ///
    /// - Detected outgoing outro: overlap = outro length, stretched by the
    ///   incoming track's quiet-intro lead (capped) so its music arrives while
    ///   the outgoing is still audible.
    /// - Contour present but the track ends hot: minimal cut, no lead — never
    ///   fade body audio early.
    /// - No outgoing contour: the default, plus the incoming lead when known.
    static func crossfadeDuration(
        loudnessLevels: [Float]?,
        trackDuration: TimeInterval,
        nextLoudnessLevels: [Float]? = nil,
        nextTrackDuration: TimeInterval? = nil
    ) -> TimeInterval {
        let onsetLead = incomingOnsetLead(
            nextLoudnessLevels: nextLoudnessLevels,
            nextTrackDuration: nextTrackDuration
        )

        guard let levels = loudnessLevels, !levels.isEmpty else {
            return clampDuration(defaultCrossfadeDuration + onsetLead)
        }

        guard let outroLength = detectedOutroLength(levels: levels, trackDuration: trackDuration) else {
            return minCrossfadeDuration
        }

        return clampDuration(outroLength + onsetLead)
    }

    /// Length in seconds of a genuine fade-out at the end of the track, or nil
    /// when the contour shows the track ending at body level (hot ending).
    static func detectedOutroLength(
        levels: [Float],
        trackDuration: TimeInterval
    ) -> TimeInterval? {
        guard let bodyLevel = bodyLevel(of: levels), bodyLevel > 0 else { return nil }
        let threshold = bodyLevel * bodyLevelFraction

        // Walk backwards from end to find fade onset (first sample >= threshold)
        var fadeStartIndex = levels.count
        for i in stride(from: levels.count - 1, through: 0, by: -1) {
            if levels[i] >= threshold {
                fadeStartIndex = i + 1
                break
            }
        }

        if fadeStartIndex >= levels.count {
            return nil
        }

        // Validate it's a real fade: the fade region should be generally decreasing
        let fadeRegion = Array(levels[fadeStartIndex...])
        if !isGenerallyDecreasing(fadeRegion) {
            return nil
        }

        let fadeFraction = Double(levels.count - fadeStartIndex) / Double(levels.count)
        return fadeFraction * trackDuration
    }

    /// Seconds of near-silent intro on the incoming track (its music onset),
    /// capped at `maxOnsetLeadSeconds`. Zero when unknown or starting hot.
    static func incomingOnsetLead(
        nextLoudnessLevels: [Float]?,
        nextTrackDuration: TimeInterval?
    ) -> TimeInterval {
        guard let levels = nextLoudnessLevels, !levels.isEmpty,
              let duration = nextTrackDuration, duration > 0,
              let bodyLevel = bodyLevel(of: levels), bodyLevel > 0 else {
            return 0
        }
        let threshold = bodyLevel * bodyLevelFraction
        guard let onsetIndex = levels.firstIndex(where: { $0 >= threshold }), onsetIndex > 0 else {
            return 0
        }
        let onsetFraction = Double(onsetIndex) / Double(levels.count)
        return min(maxOnsetLeadSeconds, onsetFraction * duration)
    }

    /// "Body level" = median of the middle 50% of samples (skip first/last
    /// quarter so intros/outros don't skew the baseline).
    private static func bodyLevel(of levels: [Float]) -> Float? {
        let quarter = levels.count / 4
        let bodySlice = Array(levels[quarter ..< levels.count - quarter])
        guard !bodySlice.isEmpty else { return nil }
        return median(bodySlice)
    }

    private static func clampDuration(_ value: TimeInterval) -> TimeInterval {
        min(maxCrossfadeDuration, max(minCrossfadeDuration, value))
    }

    // MARK: - Helpers

    static func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        }
        return sorted[count / 2]
    }

    /// Validates that an array of loudness values is generally non-increasing.
    /// Splits into 3 chunks and checks that each chunk average is not significantly
    /// higher than the previous (allows 20% tolerance for small bumps).
    static func isGenerallyDecreasing(_ values: [Float]) -> Bool {
        guard values.count >= 3 else { return true }

        let chunkSize = values.count / 3
        guard chunkSize > 0 else { return true }

        func average(_ slice: ArraySlice<Float>) -> Float {
            slice.reduce(0, +) / Float(slice.count)
        }

        let chunk1 = average(values[0 ..< chunkSize])
        let chunk2 = average(values[chunkSize ..< chunkSize * 2])
        let chunk3 = average(values[chunkSize * 2 ..< values.count])

        let tolerance: Float = 0.20
        return chunk2 <= chunk1 * (1 + tolerance) && chunk3 <= chunk2 * (1 + tolerance)
    }
}
