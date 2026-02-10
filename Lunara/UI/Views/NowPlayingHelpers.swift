import Foundation

enum NowPlayingUpNextBuilder {
    static func upNextTracks(tracks: [PlexTrack], currentRatingKey: String) -> [PlexTrack] {
        guard let index = tracks.firstIndex(where: { $0.ratingKey == currentRatingKey }) else {
            return []
        }
        return Array(tracks.dropFirst(index + 1))
    }
}

enum NowPlayingSeekDecision {
    static func shouldSeek(currentTime: TimeInterval, targetTime: TimeInterval, tolerance: TimeInterval) -> Bool {
        abs(targetTime - currentTime) > tolerance
    }
}

enum TrackArtistDisplayResolver {
    static func displayArtist(for track: PlexTrack, albumArtist: String?) -> String? {
        let trackArtistRaw = cleaned(track.originalTitle ?? track.grandparentTitle)
        guard let trackArtistRaw, !trackArtistRaw.isEmpty else {
            return nil
        }
        let trackArtist = normalized(trackArtistRaw)
        let albumArtistNormalized = normalized(cleaned(albumArtist))
        if trackArtist == albumArtistNormalized {
            return nil
        }
        return trackArtistRaw
    }

    private static func cleaned(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }

    private static func normalized(_ value: String?) -> String? {
        value?.lowercased()
    }
}
