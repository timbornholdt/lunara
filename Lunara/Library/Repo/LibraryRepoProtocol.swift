import Foundation

@MainActor
protocol LibraryRepoProtocol: AnyObject {
    func fetchAlbums() async throws -> [Album]
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
