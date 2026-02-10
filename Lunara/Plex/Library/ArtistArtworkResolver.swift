import Foundation

struct ArtistArtworkResolver {
    let artworkBuilder: PlexArtworkURLBuilder

    func artworkPath(for artist: PlexArtist) -> String? {
        if let art = artist.art, !art.isEmpty {
            return art
        }
        if let thumb = artist.thumb, !thumb.isEmpty {
            return thumb
        }
        return nil
    }

    func artworkURL(for artist: PlexArtist) -> URL? {
        guard let path = artworkPath(for: artist) else { return nil }
        return artworkBuilder.makeTranscodedArtworkURL(artPath: path)
    }
}
