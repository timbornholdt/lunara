import Foundation

// MARK: - Plex XML Response Models

/// Plex returns XML with a MediaContainer root element
struct PlexMediaContainer: Codable {
    let metadata: [PlexMetadata]?
    let directories: [PlexDirectory]?
    let machineIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case metadata = "Metadata"
        case directories = "Directory"
        case machineIdentifier
    }
}

/// Directory element (used for library sections, artists, and albums)
struct PlexDirectory: Codable {
    let key: String
    let type: String
    let title: String
    let agent: String?
    let scanner: String?
    let language: String?
    let uuid: String?

    // Album-specific metadata
    let parentTitle: String?        // Artist name
    let year: Int?
    let thumb: String?              // Thumbnail path
    let genre: String?
    let genres: [String]
    let styles: [String]
    let moods: [String]
    let collectionIDs: [String]
    let rating: Double?
    let addedAt: Int?               // Unix timestamp
    let leafCount: Int?             // Track count
    let childCount: Int?            // Direct child count (e.g., album count for collections)
    let duration: Int?              // Total duration in milliseconds
    let summary: String?
    let titleSort: String?
    let updatedAt: Int?
    let parentRatingKey: String?
    let ratingKey: String?
    let originallyAvailableAt: String?
}

/// Individual metadata item (Album, Track, Artist, etc.)
struct PlexMetadata: Codable {
    let ratingKey: String
    let title: String
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let type: String
    let index: Int?
    let parentTitle: String?
    let grandparentTitle: String?
    let originalTitle: String?
    let year: Int?
    let thumb: String?
    let duration: Int?
    let genre: String?
    let rating: Double?
    let addedAt: Int?
    let trackCount: Int?
    let albumCount: Int?
    let leafCount: Int?
    let summary: String?
    let titleSort: String?
    let updatedAt: Int?
    let key: String?
    let playlistItemID: Int?
    let composite: String?

    enum CodingKeys: String, CodingKey {
        case ratingKey
        case title
        case parentRatingKey
        case grandparentRatingKey
        case type
        case index
        case parentTitle
        case grandparentTitle
        case originalTitle
        case year
        case thumb
        case duration
        case genre
        case rating
        case addedAt
        case trackCount
        case albumCount
        case leafCount
        case summary
        case titleSort
        case updatedAt
        case key
        case playlistItemID
        case composite
    }
}

// MARK: - Plex Pin Response (JSON)

/// Plex OAuth pin endpoint returns JSON
struct PlexPinResponseJSON: Codable {
    let id: Int
    let code: String
}

/// Plex OAuth token check response (JSON)
struct PlexAuthCheckResponseJSON: Codable {
    let authToken: String?
}
