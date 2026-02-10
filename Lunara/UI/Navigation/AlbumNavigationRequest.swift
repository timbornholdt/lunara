import Foundation

struct AlbumNavigationRequest: Hashable {
    let album: PlexAlbum
    let albumRatingKeys: [String]

    static func == (lhs: AlbumNavigationRequest, rhs: AlbumNavigationRequest) -> Bool {
        lhs.album.ratingKey == rhs.album.ratingKey &&
        lhs.albumRatingKeys == rhs.albumRatingKeys
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(album.ratingKey)
        hasher.combine(albumRatingKeys)
    }
}
