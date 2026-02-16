import Foundation

/// Represents an album in the Plex library.
/// This is a pure data type shared across Library and Music domains.
struct Album: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// Plex's unique identifier for this album
    let plexID: String

    /// Album title
    let title: String

    /// Primary album artist name
    let artistName: String

    /// Release year (if available)
    let year: Int?

    /// URL to album artwork thumbnail from Plex
    let thumbURL: String?

    /// Primary genre (if available)
    let genre: String?

    /// User's star rating (0-10 scale, Plex standard)
    let rating: Int?

    /// When this album was added to the library
    let addedAt: Date?

    /// Number of tracks on this album
    let trackCount: Int

    /// Total duration of all tracks in seconds
    let duration: TimeInterval

    // MARK: - Identifiable

    var id: String { plexID }

    // MARK: - Computed Properties

    /// Human-readable duration string (e.g., "42:30")
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Album display subtitle combining artist and year
    var subtitle: String {
        if let year = year {
            return "\(artistName) • \(year)"
        }
        return artistName
    }

    /// Whether this album has been rated
    var isRated: Bool {
        rating != nil && rating! > 0
    }
}
