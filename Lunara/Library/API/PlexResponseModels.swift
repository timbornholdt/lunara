import Foundation

// MARK: - Plex XML Response Models

/// Plex returns XML with a MediaContainer root element
struct PlexMediaContainer: Codable {
    let metadata: [PlexMetadata]?
    let directories: [PlexDirectory]?

    enum CodingKeys: String, CodingKey {
        case metadata = "Metadata"
        case directories = "Directory"
    }
}

/// Directory element (used for library sections)
struct PlexDirectory: Codable {
    let key: String
    let type: String
    let title: String
    let agent: String?
    let scanner: String?
    let language: String?
    let uuid: String?
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
    let year: Int?
    let thumb: String?
    let duration: Int?
    let genre: String?
    let rating: Double?
    let addedAt: Int?
    let trackCount: Int?
    let albumCount: Int?
    let summary: String?
    let titleSort: String?
    let key: String?

    enum CodingKeys: String, CodingKey {
        case ratingKey
        case title
        case parentRatingKey
        case grandparentRatingKey
        case type
        case index
        case parentTitle
        case grandparentTitle
        case year
        case thumb
        case duration
        case genre
        case rating
        case addedAt
        case trackCount
        case albumCount
        case summary
        case titleSort
        case key
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
