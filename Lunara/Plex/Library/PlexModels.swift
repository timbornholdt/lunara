import Foundation

struct PlexAlbum: Decodable, Equatable, Sendable {
    let ratingKey: String
    let title: String
    let thumb: String?
    let art: String?
    let year: Int?
    let artist: String?
    let key: String?

    private enum CodingKeys: String, CodingKey {
        case ratingKey
        case title
        case thumb
        case art
        case year
        case artist = "parentTitle"
        case key
    }
}

struct PlexTrack: Decodable, Equatable, Sendable {
    let ratingKey: String
    let title: String
    let index: Int?
    let parentRatingKey: String?
    let duration: Int?
}
