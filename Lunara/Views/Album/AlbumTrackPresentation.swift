import Foundation

enum AlbumTrackPresentation {
    static func secondaryArtist(trackArtist: String, albumArtist: String) -> String? {
        let normalizedTrackArtist = trackArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAlbumArtist = albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTrackArtist.isEmpty else {
            return nil
        }

        guard normalizedTrackArtist.caseInsensitiveCompare(normalizedAlbumArtist) != .orderedSame else {
            return nil
        }

        return normalizedTrackArtist
    }

    static func albumDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}
