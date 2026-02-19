import Foundation
@testable import Lunara

@MainActor
final class LibraryRemoteMock: LibraryRemoteDataSource {
    var albums: [Album] = []
    var albumsByID: [String: Album] = [:]
    var tracksByAlbumID: [String: [Track]] = [:]
    var tracksByID: [String: Track] = [:]
    var streamURLByTrackID: [String: URL] = [:]
    var artworkURLByRawValue: [String: URL] = [:]

    var fetchAlbumsCallCount = 0
    var fetchAlbumRequests: [String] = []
    var fetchTracksRequests: [String] = []
    var fetchTrackRequests: [String] = []
    var streamURLRequests: [String] = []
    var artworkURLRequests: [String?] = []

    var fetchAlbumsError: LibraryError?
    var fetchTracksErrorByAlbumID: [String: LibraryError] = [:]
    var fetchTrackErrorByID: [String: LibraryError] = [:]
    var streamURLError: LibraryError?
    var artworkURLError: LibraryError?

    func fetchAlbums() async throws -> [Album] {
        fetchAlbumsCallCount += 1
        if let fetchAlbumsError {
            throw fetchAlbumsError
        }
        return albums
    }

    func fetchAlbum(id albumID: String) async throws -> Album? {
        fetchAlbumRequests.append(albumID)
        return albumsByID[albumID]
    }

    func fetchTracks(forAlbum albumID: String) async throws -> [Track] {
        fetchTracksRequests.append(albumID)
        if let error = fetchTracksErrorByAlbumID[albumID] {
            throw error
        }
        return tracksByAlbumID[albumID] ?? []
    }

    func fetchTrack(id trackID: String) async throws -> Track? {
        fetchTrackRequests.append(trackID)
        if let error = fetchTrackErrorByID[trackID] {
            throw error
        }
        return tracksByID[trackID]
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

    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? {
        artworkURLRequests.append(rawValue)
        if let artworkURLError {
            throw artworkURLError
        }
        guard let rawValue else {
            return nil
        }
        return artworkURLByRawValue[rawValue]
    }
}

@MainActor
final class LibraryStoreMock: LibraryStoreProtocol {
    var albumsByPage: [Int: [Album]] = [:]
    var albumByID: [String: Album] = [:]
    var tracksByAlbumID: [String: [Track]] = [:]
    var artistsByID: [String: Artist] = [:]
    var collectionsByID: [String: Collection] = [:]
    var tracksByID: [String: Track] = [:]
    var cachedArtists: [Artist] = []
    var cachedCollections: [Collection] = []
    var searchedAlbumsByQuery: [String: [Album]] = [:]
    var searchedArtistsByQuery: [String: [Artist]] = [:]
    var searchedCollectionsByQuery: [String: [Collection]] = [:]
    var lastRefresh: Date?

    var fetchAlbumsRequests: [LibraryPage] = []
    var fetchTrackRequests: [String] = []
    var trackLookupRequests: [String] = []
    var collectionLookupRequests: [String] = []
    var searchedAlbumQueries: [String] = []
    var searchedArtistQueries: [String] = []
    var searchedCollectionQueries: [String] = []
    var replaceLibraryCallCount = 0
    var replacedSnapshot: LibrarySnapshot?
    var replacedRefreshedAt: Date?
    var begunSyncRuns: [LibrarySyncRun] = []
    var upsertAlbumsCalls: [([Album], LibrarySyncRun)] = []
    var upsertTracksCalls: [([Track], LibrarySyncRun)] = []
    var markAlbumsSeenCalls: [([String], LibrarySyncRun)] = []
    var markTracksSeenCalls: [([String], LibrarySyncRun)] = []
    var pruneRowsNotSeenCalls: [LibrarySyncRun] = []
    var completeIncrementalSyncCalls: [(LibrarySyncRun, Date)] = []
    var syncCheckpointByKey: [String: LibrarySyncCheckpoint] = [:]
    var pruneResult: LibrarySyncPruneResult = .empty
    var artworkPathByKey: [ArtworkKey: String] = [:]
    var setArtworkPathCalls: [(ArtworkKey, String)] = []
    var deletedArtworkPathKeys: [ArtworkKey] = []

    var replaceLibraryError: LibraryError?
    var beginIncrementalSyncError: LibraryError?
    var upsertAlbumsError: LibraryError?
    var upsertTracksError: LibraryError?
    var markAlbumsSeenError: LibraryError?
    var markTracksSeenError: LibraryError?
    var pruneRowsNotSeenError: LibraryError?
    var setSyncCheckpointError: LibraryError?
    var completeIncrementalSyncError: LibraryError?

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

    func track(id: String) async throws -> Track? {
        trackLookupRequests.append(id)
        return tracksByID[id]
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

    func collection(id: String) async throws -> Collection? {
        collectionLookupRequests.append(id)
        return collectionsByID[id]
    }

    func searchAlbums(query: String) async throws -> [Album] {
        searchedAlbumQueries.append(query)
        return searchedAlbumsByQuery[query] ?? []
    }

    func searchArtists(query: String) async throws -> [Artist] {
        searchedArtistQueries.append(query)
        return searchedArtistsByQuery[query] ?? []
    }

    func searchCollections(query: String) async throws -> [Collection] {
        searchedCollectionQueries.append(query)
        return searchedCollectionsByQuery[query] ?? []
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

    func beginIncrementalSync(startedAt: Date) async throws -> LibrarySyncRun {
        if let beginIncrementalSyncError {
            throw beginIncrementalSyncError
        }
        let run = LibrarySyncRun(id: "mock-sync-\(begunSyncRuns.count + 1)", startedAt: startedAt)
        begunSyncRuns.append(run)
        return run
    }

    func upsertAlbums(_ albums: [Album], in run: LibrarySyncRun) async throws {
        if let upsertAlbumsError {
            throw upsertAlbumsError
        }
        upsertAlbumsCalls.append((albums, run))
        for album in albums {
            albumByID[album.plexID] = album
        }
        albumsByPage = [
            1: albumByID.values.sorted {
                if $0.artistName != $1.artistName {
                    return $0.artistName < $1.artistName
                }
                if $0.title != $1.title {
                    return $0.title < $1.title
                }
                return $0.plexID < $1.plexID
            }
        ]
    }

    func upsertTracks(_ tracks: [Track], in run: LibrarySyncRun) async throws {
        if let upsertTracksError {
            throw upsertTracksError
        }
        upsertTracksCalls.append((tracks, run))
        for track in tracks {
            tracksByID[track.plexID] = track
        }
        tracksByAlbumID = Dictionary(grouping: tracksByID.values, by: \.albumID)
    }

    func markAlbumsSeen(_ albumIDs: [String], in run: LibrarySyncRun) async throws {
        if let markAlbumsSeenError {
            throw markAlbumsSeenError
        }
        markAlbumsSeenCalls.append((albumIDs, run))
    }

    func markTracksSeen(_ trackIDs: [String], in run: LibrarySyncRun) async throws {
        if let markTracksSeenError {
            throw markTracksSeenError
        }
        markTracksSeenCalls.append((trackIDs, run))
    }

    func pruneRowsNotSeen(in run: LibrarySyncRun) async throws -> LibrarySyncPruneResult {
        if let pruneRowsNotSeenError {
            throw pruneRowsNotSeenError
        }
        pruneRowsNotSeenCalls.append(run)
        for albumID in pruneResult.prunedAlbumIDs {
            albumByID.removeValue(forKey: albumID)
            tracksByAlbumID.removeValue(forKey: albumID)
        }
        for trackID in pruneResult.prunedTrackIDs {
            tracksByID.removeValue(forKey: trackID)
        }
        tracksByAlbumID = Dictionary(grouping: tracksByID.values, by: \.albumID)
        albumsByPage = [
            1: albumByID.values.sorted {
                if $0.artistName != $1.artistName {
                    return $0.artistName < $1.artistName
                }
                if $0.title != $1.title {
                    return $0.title < $1.title
                }
                return $0.plexID < $1.plexID
            }
        ]
        return pruneResult
    }

    func setSyncCheckpoint(_ checkpoint: LibrarySyncCheckpoint, in run: LibrarySyncRun?) async throws {
        if let setSyncCheckpointError {
            throw setSyncCheckpointError
        }
        syncCheckpointByKey[checkpoint.key] = checkpoint
    }

    func syncCheckpoint(forKey key: String) async throws -> LibrarySyncCheckpoint? {
        syncCheckpointByKey[key]
    }

    func completeIncrementalSync(_ run: LibrarySyncRun, refreshedAt: Date) async throws {
        if let completeIncrementalSyncError {
            throw completeIncrementalSyncError
        }
        completeIncrementalSyncCalls.append((run, refreshedAt))
        lastRefresh = refreshedAt
    }

    func artworkPath(for key: ArtworkKey) async throws -> String? {
        artworkPathByKey[key]
    }

    func setArtworkPath(_ path: String, for key: ArtworkKey) async throws {
        artworkPathByKey[key] = path
        setArtworkPathCalls.append((key, path))
    }

    func deleteArtworkPath(for key: ArtworkKey) async throws {
        artworkPathByKey[key] = nil
        deletedArtworkPathKeys.append(key)
    }
}
