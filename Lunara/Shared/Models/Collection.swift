import Foundation

/// Represents a Plex collection (user-curated grouping of albums).
/// This is a pure data type shared across Library and Music domains.
struct Collection: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// Plex's unique identifier for this collection
    let plexID: String

    /// Collection title
    let title: String

    /// URL to collection artwork thumbnail from Plex
    let thumbURL: String?

    /// Optional description or summary of the collection
    let summary: String?

    /// Number of albums in this collection
    let albumCount: Int

    /// When this collection was created or last modified
    let updatedAt: Date?

    // MARK: - Identifiable

    var id: String { plexID }

    // MARK: - Computed Properties

    /// Display subtitle showing album count
    var subtitle: String {
        let count = albumCount
        let plural = count == 1 ? "album" : "albums"
        return "\(count) \(plural)"
    }

    /// Whether this is one of the pinned "featured" collections
    /// Note: This is a display hint; actual pinning logic lives in the Library domain
    var isPinnedCollection: Bool {
        title == "Current Vibes" || title == "The Key Albums"
    }
}
