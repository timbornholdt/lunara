import Foundation

/// Represents an artist in the Plex library.
/// This is a pure data type shared across Library and Music domains.
struct Artist: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// Plex's unique identifier for this artist
    let plexID: String

    /// Artist name as displayed
    let name: String

    /// Sort name for alphabetical ordering (e.g., "Beatles, The")
    let sortName: String?

    /// URL to artist artwork thumbnail from Plex
    let thumbURL: String?

    /// Primary genre associated with this artist
    let genre: String?

    /// Artist biography or summary text
    let summary: String?

    /// Number of albums by this artist in the library
    let albumCount: Int

    // MARK: - Identifiable

    var id: String { plexID }

    // MARK: - Computed Properties

    /// Name to use for alphabetical sorting
    var effectiveSortName: String {
        sortName ?? name
    }

    /// Whether this artist has biographical information
    var hasSummary: Bool {
        summary != nil && !summary!.isEmpty
    }
}
