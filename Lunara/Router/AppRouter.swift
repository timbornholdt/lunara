import Foundation

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
        guard !tracks.isEmpty else { return }

        var items: [QueueItem] = []
        items.reserveCapacity(tracks.count)

        for track in tracks {
            let url = try await resolveURL(for: track)
            items.append(QueueItem(trackID: track.plexID, url: url))
        }

        queue.playNow(items)
    }
}
