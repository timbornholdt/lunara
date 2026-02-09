import Foundation

struct AlbumArtworkResolver {
    let artworkBuilder: PlexArtworkURLBuilder

    func artworkURL(for album: PlexAlbum) -> URL? {
        if let thumb = album.thumb {
            return artworkBuilder.makeTranscodedArtworkURL(artPath: thumb)
        }
        if let art = album.art {
            return artworkBuilder.makeTranscodedArtworkURL(artPath: art)
        }
        return nil
    }
}
