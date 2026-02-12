import Foundation

enum OfflineAlbumIdentity {
    static func make(for album: PlexAlbum) -> String {
        if let guid = album.guid?.trimmingCharacters(in: .whitespacesAndNewlines),
           guid.isEmpty == false {
            return guid
        }

        let title = album.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let artist = album.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let year = album.year.map(String.init) ?? ""
        return "\(title)|\(artist)|\(year)"
    }
}
