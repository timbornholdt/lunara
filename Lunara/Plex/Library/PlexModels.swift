import Foundation

struct PlexTag: Codable, Equatable, Sendable {
    let tag: String
}

struct PlexCollection: Codable, Equatable, Sendable {
    let ratingKey: String
    let title: String
    let thumb: String?
    let art: String?
    let updatedAt: Int?
    let key: String?

    private enum CodingKeys: String, CodingKey {
        case ratingKey
        case title
        case thumb
        case art
        case updatedAt
        case key
    }
}

struct PlexArtist: Codable, Equatable, Sendable {
    let ratingKey: String
    let title: String
    let titleSort: String?
    let summary: String?
    let thumb: String?
    let art: String?
    let country: String?
    let genres: [PlexTag]?
    let userRating: Double?
    let rating: Double?
    let albumCount: Int?
    let trackCount: Int?
    let addedAt: Int?
    let updatedAt: Int?

    init(
        ratingKey: String,
        title: String,
        titleSort: String?,
        summary: String?,
        thumb: String?,
        art: String?,
        country: String?,
        genres: [PlexTag]?,
        userRating: Double?,
        rating: Double?,
        albumCount: Int?,
        trackCount: Int?,
        addedAt: Int?,
        updatedAt: Int?
    ) {
        self.ratingKey = ratingKey
        self.title = title
        self.titleSort = titleSort
        self.summary = summary
        self.thumb = thumb
        self.art = art
        self.country = country
        self.genres = genres
        self.userRating = userRating
        self.rating = rating
        self.albumCount = albumCount
        self.trackCount = trackCount
        self.addedAt = addedAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case ratingKey
        case title
        case titleSort
        case summary
        case thumb
        case art
        case country
        case genres = "Genre"
        case userRating
        case rating = "Rating"
        case ratingLower = "rating"
        case albumCount
        case trackCount
        case addedAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ratingKey = try container.decode(String.self, forKey: .ratingKey)
        title = try container.decode(String.self, forKey: .title)
        titleSort = try container.decodeIfPresent(String.self, forKey: .titleSort)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        thumb = try container.decodeIfPresent(String.self, forKey: .thumb)
        art = try container.decodeIfPresent(String.self, forKey: .art)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        genres = try container.decodeIfPresent([PlexTag].self, forKey: .genres)
        userRating = try container.decodeIfPresent(Double.self, forKey: .userRating)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
            ?? container.decodeIfPresent(Double.self, forKey: .ratingLower)
        albumCount = try container.decodeIfPresent(Int.self, forKey: .albumCount)
        trackCount = try container.decodeIfPresent(Int.self, forKey: .trackCount)
        addedAt = try container.decodeIfPresent(Int.self, forKey: .addedAt)
        updatedAt = try container.decodeIfPresent(Int.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ratingKey, forKey: .ratingKey)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(titleSort, forKey: .titleSort)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(thumb, forKey: .thumb)
        try container.encodeIfPresent(art, forKey: .art)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(genres, forKey: .genres)
        try container.encodeIfPresent(userRating, forKey: .userRating)
        try container.encodeIfPresent(rating, forKey: .rating)
        try container.encodeIfPresent(albumCount, forKey: .albumCount)
        try container.encodeIfPresent(trackCount, forKey: .trackCount)
        try container.encodeIfPresent(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

struct PlexAlbum: Codable, Equatable, Sendable {
    let ratingKey: String
    let title: String
    let thumb: String?
    let art: String?
    let year: Int?
    let duration: Int?
    let originallyAvailableAt: String?
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

    init(
        ratingKey: String,
        title: String,
        thumb: String?,
        art: String?,
        year: Int?,
        duration: Int? = nil,
        originallyAvailableAt: String? = nil,
        artist: String?,
        titleSort: String?,
        originalTitle: String?,
        editionTitle: String?,
        guid: String?,
        librarySectionID: Int?,
        parentRatingKey: String?,
        studio: String?,
        summary: String?,
        genres: [PlexTag]?,
        styles: [PlexTag]?,
        moods: [PlexTag]?,
        rating: Double?,
        userRating: Double?,
        key: String?
    ) {
        self.ratingKey = ratingKey
        self.title = title
        self.thumb = thumb
        self.art = art
        self.year = year
        self.duration = duration
        self.originallyAvailableAt = originallyAvailableAt
        self.artist = artist
        self.titleSort = titleSort
        self.originalTitle = originalTitle
        self.editionTitle = editionTitle
        self.guid = guid
        self.librarySectionID = librarySectionID
        self.parentRatingKey = parentRatingKey
        self.studio = studio
        self.summary = summary
        self.genres = genres
        self.styles = styles
        self.moods = moods
        self.rating = rating
        self.userRating = userRating
        self.key = key
    }

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
        case duration
        case originallyAvailableAt
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

struct PlexTrack: Codable, Equatable, Sendable {
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

struct PlexTrackMedia: Codable, Equatable, Sendable {
    let parts: [PlexTrackPart]

    private enum CodingKeys: String, CodingKey {
        case parts = "Part"
    }
}

struct PlexTrackPart: Codable, Equatable, Sendable {
    let key: String
}
