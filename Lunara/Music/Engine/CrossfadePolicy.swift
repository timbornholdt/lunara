import Foundation

enum TransitionStyle: Equatable, Sendable {
    case gapless
    case crossfade(startTime: TimeInterval, duration: TimeInterval)
}

struct CrossfadePolicy: Sendable {
    static let defaultCrossfadeDuration: TimeInterval = 3
    static let minCrossfadeDuration: TimeInterval = 1
    static let maxCrossfadeDuration: TimeInterval = 8
    static let loudnessThreshold: Float = 0.15

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

        // Scan from end of loudness array to find where level drops below threshold
        var fadeStartIndex = levels.count
        for i in stride(from: levels.count - 1, through: 0, by: -1) {
            if levels[i] >= loudnessThreshold {
                fadeStartIndex = i + 1
                break
            }
        }

        if fadeStartIndex >= levels.count {
            return defaultCrossfadeDuration
        }

        let fadeFraction = Double(levels.count - fadeStartIndex) / Double(levels.count)
        let computedDuration = fadeFraction * trackDuration

        return min(maxCrossfadeDuration, max(minCrossfadeDuration, computedDuration))
    }
}
