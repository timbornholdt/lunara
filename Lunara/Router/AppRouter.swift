import Foundation

@MainActor
protocol LibraryRepoProtocol: AnyObject {
    func tracks(forAlbum albumID: String) async throws -> [Track]
    func streamURL(for track: Track) async throws -> URL
}

extension PlexAPIClient: LibraryRepoProtocol {
    func tracks(forAlbum albumID: String) async throws -> [Track] {
        try await fetchTracks(forAlbum: albumID)
    }

    func streamURL(for track: Track) async throws -> URL {
        try await streamURL(forTrack: track)
    }
}

@MainActor
final class AppRouter {
    private let library: LibraryRepoProtocol
    private let queue: QueueManagerProtocol

    init(library: LibraryRepoProtocol, queue: QueueManagerProtocol) {
        self.library = library
        self.queue = queue
    }

    func resolveURL(for track: Track) async throws -> URL {
        try await library.streamURL(for: track)
    }

    func playAlbum(_ album: Album) async throws {
        let tracks = try await library.tracks(forAlbum: album.plexID)

        var items: [QueueItem] = []
        items.reserveCapacity(tracks.count)

        for track in tracks {
            let url = try await resolveURL(for: track)
            items.append(QueueItem(trackID: track.plexID, url: url))
        }

        queue.playNow(items)
    }
}
