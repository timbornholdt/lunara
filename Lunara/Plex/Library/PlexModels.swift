import Foundation

struct PlexAlbum: Decodable, Equatable, Sendable {
    let ratingKey: String
    let title: String
    let thumb: String?
    let art: String?
    let year: Int?
    let key: String?
}

struct PlexTrack: Decodable, Equatable, Sendable {
    let ratingKey: String
    let title: String
    let index: Int?
    let parentRatingKey: String?
    let duration: Int?
}
