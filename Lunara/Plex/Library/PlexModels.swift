import Foundation

struct PlexTag: Decodable, Equatable, Sendable {
    let tag: String
}

struct PlexAlbum: Decodable, Equatable, Sendable {
    let ratingKey: String
    let title: String
    let thumb: String?
    let art: String?
    let year: Int?
    let artist: String?
    let summary: String?
    let genres: [PlexTag]?
    let styles: [PlexTag]?
    let moods: [PlexTag]?
    let rating: Double?
    let userRating: Double?
    let key: String?

    private enum CodingKeys: String, CodingKey {
        case ratingKey
        case title
        case thumb
        case art
        case year
        case artist = "parentTitle"
        case summary
        case genres = "Genre"
        case styles = "Style"
        case moods = "Mood"
        case rating
        case userRating
        case key
    }
}

struct PlexTrack: Decodable, Equatable, Sendable {
    let ratingKey: String
    let title: String
    let index: Int?
    let parentRatingKey: String?
    let duration: Int?
    let media: [PlexTrackMedia]?

    private enum CodingKeys: String, CodingKey {
        case ratingKey
        case title
        case index
        case parentRatingKey
        case duration
        case media = "Media"
    }
}

struct PlexTrackMedia: Decodable, Equatable, Sendable {
    let parts: [PlexTrackPart]

    private enum CodingKeys: String, CodingKey {
        case parts = "Part"
    }
}

struct PlexTrackPart: Decodable, Equatable, Sendable {
    let key: String
}
