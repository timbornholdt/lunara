import Foundation
@testable import Lunara

@MainActor
final class LibraryRemoteMock: LibraryRemoteDataSource {
    var albums: [Album] = []
    var tracksByAlbumID: [String: [Track]] = [:]
    var streamURLByTrackID: [String: URL] = [:]

    var fetchAlbumsCallCount = 0
    var fetchTracksRequests: [String] = []
    var streamURLRequests: [String] = []

    var fetchAlbumsError: LibraryError?
    var fetchTracksErrorByAlbumID: [String: LibraryError] = [:]
    var streamURLError: LibraryError?

    func fetchAlbums() async throws -> [Album] {
        fetchAlbumsCallCount += 1
        if let fetchAlbumsError {
            throw fetchAlbumsError
        }
        return albums
    }

    func fetchTracks(forAlbum albumID: String) async throws -> [Track] {
        fetchTracksRequests.append(albumID)
        if let error = fetchTracksErrorByAlbumID[albumID] {
            throw error
        }
        return tracksByAlbumID[albumID] ?? []
    }

    func streamURL(forTrack track: Track) async throws -> URL {
        streamURLRequests.append(track.plexID)
        if let streamURLError {
            throw streamURLError
        }
        guard let url = streamURLByTrackID[track.plexID] else {
            throw LibraryError.resourceNotFound(type: "track", id: track.plexID)
        }
        return url
    }
}

@MainActor
final class LibraryStoreMock: LibraryStoreProtocol {
    var albumsByPage: [Int: [Album]] = [:]
    var albumByID: [String: Album] = [:]
    var tracksByAlbumID: [String: [Track]] = [:]
    var artistsByID: [String: Artist] = [:]
    var collectionsByID: [String: Collection] = [:]
    var cachedArtists: [Artist] = []
    var cachedCollections: [Collection] = []
    var lastRefresh: Date?

    var fetchAlbumsRequests: [LibraryPage] = []
    var fetchTrackRequests: [String] = []
    var replaceLibraryCallCount = 0
    var replacedSnapshot: LibrarySnapshot?
    var replacedRefreshedAt: Date?

    var replaceLibraryError: LibraryError?

    func fetchAlbums(page: LibraryPage) async throws -> [Album] {
        fetchAlbumsRequests.append(page)
        return albumsByPage[page.number] ?? []
    }

    func fetchAlbum(id: String) async throws -> Album? {
        albumByID[id]
    }

    func fetchTracks(forAlbum albumID: String) async throws -> [Track] {
        fetchTrackRequests.append(albumID)
        return tracksByAlbumID[albumID] ?? []
    }

    func fetchArtists() async throws -> [Artist] {
        if !cachedArtists.isEmpty {
            return cachedArtists
        }
        return artistsByID.values.sorted { $0.name < $1.name }
    }

    func fetchArtist(id: String) async throws -> Artist? {
        artistsByID[id]
    }

    func fetchCollections() async throws -> [Collection] {
        if !cachedCollections.isEmpty {
            return cachedCollections
        }
        return collectionsByID.values.sorted { $0.title < $1.title }
    }

    func replaceLibrary(with snapshot: LibrarySnapshot, refreshedAt: Date) async throws {
        if let replaceLibraryError {
            throw replaceLibraryError
        }
        replaceLibraryCallCount += 1
        replacedSnapshot = snapshot
        replacedRefreshedAt = refreshedAt
        albumsByPage = [1: snapshot.albums]
        albumByID = Dictionary(uniqueKeysWithValues: snapshot.albums.map { ($0.plexID, $0) })
        tracksByAlbumID = Dictionary(grouping: snapshot.tracks, by: \.albumID)
        cachedArtists = snapshot.artists
        cachedCollections = snapshot.collections
        lastRefresh = refreshedAt
    }

    func lastRefreshDate() async throws -> Date? {
        lastRefresh
    }

    func artworkPath(for key: ArtworkKey) async throws -> String? {
        nil
    }

    func setArtworkPath(_ path: String, for key: ArtworkKey) async throws { }
    func deleteArtworkPath(for key: ArtworkKey) async throws { }
}
