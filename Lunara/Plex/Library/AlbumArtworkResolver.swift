import Foundation

struct AlbumArtworkResolver {
    let artworkBuilder: PlexArtworkURLBuilder

    func artworkPath(for album: PlexAlbum) -> String? {
        if let thumb = album.thumb, !thumb.isEmpty {
            return thumb
        }
        if let art = album.art, !art.isEmpty {
            return art
        }
        return nil
    }

    func artworkURL(for album: PlexAlbum) -> URL? {
        guard let path = artworkPath(for: album) else { return nil }
        return artworkBuilder.makeTranscodedArtworkURL(artPath: path)
    }
}
