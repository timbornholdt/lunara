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

    static func transition(
        currentAlbumID: String,
        currentTrackNumber: Int,
        nextAlbumID: String,
        nextTrackNumber: Int,
        currentTrackDuration: TimeInterval,
        loudnessLevels: [Float]?
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
            trackDuration: currentTrackDuration
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

    static func crossfadeDuration(
        loudnessLevels: [Float]?,
        trackDuration: TimeInterval
    ) -> TimeInterval {
        guard let levels = loudnessLevels, !levels.isEmpty else {
            return defaultCrossfadeDuration
        }

        // Compute "body level" = median of middle 50% of samples
        // (skip first/last quarter to avoid intros/outros skewing the baseline)
        let quarter = levels.count / 4
        let bodySlice = Array(levels[quarter ..< levels.count - quarter])
        guard !bodySlice.isEmpty else { return defaultCrossfadeDuration }

        let bodyLevel = median(bodySlice)
        guard bodyLevel > 0 else { return defaultCrossfadeDuration }

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
            return defaultCrossfadeDuration
        }

        // Validate it's a real fade: the fade region should be generally decreasing
        let fadeRegion = Array(levels[fadeStartIndex...])
        if !isGenerallyDecreasing(fadeRegion) {
            return defaultCrossfadeDuration
        }

        let fadeFraction = Double(levels.count - fadeStartIndex) / Double(levels.count)
        let computedDuration = fadeFraction * trackDuration

        return min(maxCrossfadeDuration, max(minCrossfadeDuration, computedDuration))
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
