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
}
