import Foundation

/// Represents a track in the Plex library.
/// This is a pure data type shared across Library and Music domains.
struct Track: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// Plex's unique identifier for this track
    let plexID: String

    /// ID of the album this track belongs to
    let albumID: String

    /// Track title
    let title: String

    /// Track number within the album
    let trackNumber: Int

    /// Track duration in seconds
    let duration: TimeInterval

    /// Track artist name (may differ from album artist for compilations)
    let artistName: String

    /// Plex media key used for URL construction
    let key: String

    /// URL to track-specific artwork (optional, usually inherits from album)
    let thumbURL: String?

    // MARK: - Identifiable

    var id: String { plexID }

    // MARK: - Computed Properties

    /// Human-readable duration string (e.g., "3:42")
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Track display with number (e.g., "1. Song Title")
    var displayTitle: String {
        "\(trackNumber). \(title)"
    }
}
