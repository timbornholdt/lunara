import Foundation

struct Playlist: Identifiable, Equatable, Hashable, Sendable {
    let plexID: String
    let title: String
    let trackCount: Int
    let updatedAt: Date?
    let thumbURL: String?

    var id: String { plexID }

    var subtitle: String {
        let plural = trackCount == 1 ? "song" : "songs"
        return "\(trackCount) \(plural)"
    }

    var isPinnedPlaylist: Bool {
        title == "Chopping Block" || title == "Recently Added"
    }

    init(snapshot: LibraryPlaylistSnapshot) {
        plexID = snapshot.plexID
        title = snapshot.title
        trackCount = snapshot.trackCount
        updatedAt = snapshot.updatedAt
        thumbURL = snapshot.thumbURL
    }

    init(plexID: String, title: String, trackCount: Int, updatedAt: Date?, thumbURL: String? = nil) {
        self.plexID = plexID
        self.title = title
        self.trackCount = trackCount
        self.updatedAt = updatedAt
        self.thumbURL = thumbURL
    }
}
