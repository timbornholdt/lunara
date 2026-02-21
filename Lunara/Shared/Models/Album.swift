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

    /// Full release date (if available from Plex's originallyAvailableAt)
    let releaseDate: Date?

    /// URL to album artwork thumbnail from Plex
    let thumbURL: String?

    /// Primary genre (if available)
    let genre: String?

    /// Album review/summary text from metadata providers.
    let review: String?

    /// All reported genres for this album.
    let genres: [String]

    /// All reported styles for this album.
    let styles: [String]

    /// All reported moods for this album.
    let moods: [String]

    /// User's star rating (0-10 scale, Plex standard)
    let rating: Int?

    /// When this album was added to the library
    let addedAt: Date?

    /// Number of tracks on this album
    let trackCount: Int

    /// Total duration of all tracks in seconds
    let duration: TimeInterval

    init(
        plexID: String,
        title: String,
        artistName: String,
        year: Int?,
        releaseDate: Date? = nil,
        thumbURL: String?,
        genre: String?,
        rating: Int?,
        addedAt: Date?,
        trackCount: Int,
        duration: TimeInterval,
        review: String? = nil,
        genres: [String] = [],
        styles: [String] = [],
        moods: [String] = []
    ) {
        self.plexID = plexID
        self.title = title
        self.artistName = artistName
        self.year = year
        self.releaseDate = releaseDate
        self.thumbURL = thumbURL
        self.genre = genre
        self.rating = rating
        self.addedAt = addedAt
        self.trackCount = trackCount
        self.duration = duration
        self.review = review
        self.genres = genres
        self.styles = styles
        self.moods = moods
    }

    // MARK: - Identifiable

    var id: String { plexID }

    // MARK: - Computed Properties

    /// Human-readable duration string (e.g., "42:30")
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Album display subtitle combining artist and release date/year
    var subtitle: String {
        if let releaseDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "\(artistName) • \(formatter.string(from: releaseDate))"
        }
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
