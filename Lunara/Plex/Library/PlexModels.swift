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
    let titleSort: String?
    let originalTitle: String?
    let editionTitle: String?
    let guid: String?
    let librarySectionID: Int?
    let parentRatingKey: String?
    let studio: String?
    let summary: String?
    let genres: [PlexTag]?
    let styles: [PlexTag]?
    let moods: [PlexTag]?
    let rating: Double?
    let userRating: Double?
    let key: String?

    var dedupIdentity: String {
        if let guid, !guid.isEmpty {
            return guid
        }
        let titleKey = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let artistKey = artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let yearKey = year.map(String.init) ?? ""
        return "\(titleKey)|\(artistKey)|\(yearKey)"
    }

    private enum CodingKeys: String, CodingKey {
        case ratingKey
        case title
        case thumb
        case art
        case year
        case artist = "parentTitle"
        case titleSort
        case originalTitle
        case editionTitle
        case guid
        case librarySectionID
        case parentRatingKey
        case studio
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
    let parentIndex: Int?
    let parentRatingKey: String?
    let duration: Int?
    let media: [PlexTrackMedia]?
    let originalTitle: String?
    let grandparentTitle: String?

    init(
        ratingKey: String,
        title: String,
        index: Int?,
        parentIndex: Int?,
        parentRatingKey: String?,
        duration: Int?,
        media: [PlexTrackMedia]?,
        originalTitle: String? = nil,
        grandparentTitle: String? = nil
    ) {
        self.ratingKey = ratingKey
        self.title = title
        self.index = index
        self.parentIndex = parentIndex
        self.parentRatingKey = parentRatingKey
        self.duration = duration
        self.media = media
        self.originalTitle = originalTitle
        self.grandparentTitle = grandparentTitle
    }

    private enum CodingKeys: String, CodingKey {
        case ratingKey
        case title
        case index
        case parentIndex
        case parentRatingKey
        case duration
        case media = "Media"
        case originalTitle
        case grandparentTitle
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
