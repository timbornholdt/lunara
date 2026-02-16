import Foundation

enum NowPlayingUpNextBuilder {
    struct Item: Equatable, Sendable, Identifiable {
        let id: Int
        let absoluteIndex: Int
        let track: PlexTrack
    }

    static func upNextTracks(tracks: [PlexTrack], currentRatingKey: String) -> [PlexTrack] {
        guard let index = tracks.firstIndex(where: { $0.ratingKey == currentRatingKey }) else {
            return []
        }
        return Array(tracks.dropFirst(index + 1))
    }

    static func upNextItems(tracks: [PlexTrack], currentIndex: Int?, limit: Int? = nil) -> [Item] {
        guard let currentIndex, currentIndex >= 0, currentIndex < tracks.count else {
            return []
        }
        let start = currentIndex + 1
        guard start < tracks.count else {
            return []
        }
        let allItems = Array(tracks.enumerated().dropFirst(start)).map { index, track in
            Item(id: index, absoluteIndex: index, track: track)
        }
        if let limit, allItems.count > limit {
            return Array(allItems.prefix(limit))
        }
        return allItems
    }

    static func remainingCount(tracks: [PlexTrack], currentIndex: Int?, limit: Int) -> Int {
        guard let currentIndex, currentIndex >= 0, currentIndex < tracks.count else {
            return 0
        }
        let totalUpNext = tracks.count - currentIndex - 1
        return max(totalUpNext - limit, 0)
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
