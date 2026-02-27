import Foundation
@testable import Lunara

@MainActor
final class LibraryRemoteMock: LibraryRemoteDataSource {
    var albums: [Album] = []
    var artists: [Artist] = []
    var collections: [Collection] = []
    var playlists: [LibraryRemotePlaylist] = []
    var playlistItemsByPlaylistID: [String: [LibraryRemotePlaylistItem]] = [:]
    var albumsByID: [String: Album] = [:]
    var tracksByAlbumID: [String: [Track]] = [:]
    var tracksByID: [String: Track] = [:]
    var streamURLByTrackID: [String: URL] = [:]
    var artworkURLByRawValue: [String: URL] = [:]
    var fetchAlbumsCallCount = 0
    var fetchArtistsCallCount = 0
    var fetchCollectionsCallCount = 0
    var fetchAlbumRequests: [String] = []
    var fetchPlaylistItemsRequests: [String] = []
    var fetchPlaylistsCallCount = 0
    var fetchTracksRequests: [String] = []
    var fetchTrackRequests: [String] = []
    var streamURLRequests: [String] = []
    var artworkURLRequests: [String?] = []

    var fetchAlbumsError: LibraryError?
    var fetchArtistsError: LibraryError?
    var fetchCollectionsError: LibraryError?
    var fetchPlaylistsError: LibraryError?
    var fetchPlaylistItemsErrorByID: [String: LibraryError] = [:]
    var fetchTracksErrorByAlbumID: [String: LibraryError] = [:]
    var fetchAlbumErrorByID: [String: LibraryError] = [:]
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
        if let error = fetchAlbumErrorByID[albumID] {
            throw error
        }
        return albumsByID[albumID]
    }

    func fetchArtists() async throws -> [Artist] {
        fetchArtistsCallCount += 1
        if let fetchArtistsError {
            throw fetchArtistsError
        }
        return artists
    }

    var collectionAlbumIDsByCollectionID: [String: [String]] = [:]
    var fetchCollectionAlbumIDsRequests: [String] = []

    func fetchCollections() async throws -> [Collection] {
        fetchCollectionsCallCount += 1
        if let fetchCollectionsError {
            throw fetchCollectionsError
        }
        return collections
    }

    func fetchCollectionAlbumIDs(collectionID: String) async throws -> [String] {
        fetchCollectionAlbumIDsRequests.append(collectionID)
        return collectionAlbumIDsByCollectionID[collectionID] ?? []
    }

    func fetchPlaylists() async throws -> [LibraryRemotePlaylist] {
        fetchPlaylistsCallCount += 1
        if let fetchPlaylistsError {
            throw fetchPlaylistsError
        }
        return playlists
    }

    func fetchPlaylistItems(playlistID: String) async throws -> [LibraryRemotePlaylistItem] {
        fetchPlaylistItemsRequests.append(playlistID)
        if let error = fetchPlaylistItemsErrorByID[playlistID] {
            throw error
        }
        return playlistItemsByPlaylistID[playlistID] ?? []
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

    func fetchAlbumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] { [] }
    func fetchLoudnessLevels(trackID: String, sampleCount: Int) async throws -> [Float]? { nil }
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
    var cachedPlaylists: [LibraryPlaylistSnapshot] = []
    var cachedPlaylistItemsByPlaylistID: [String: [LibraryPlaylistItemSnapshot]] = [:]
    var fetchPlaylistsCalls = 0
    var fetchPlaylistItemsRequests: [String] = []
    var searchedAlbumsByQuery: [String: [Album]] = [:]
    var queriedAlbumsByFilter: [AlbumQueryFilter: [Album]] = [:]
    var searchedArtistsByQuery: [String: [Artist]] = [:]
    var searchedCollectionsByQuery: [String: [Collection]] = [:]
    var lastRefresh: Date?

    var fetchAlbumsRequests: [LibraryPage] = []
    var fetchTrackRequests: [String] = []
    var trackLookupRequests: [String] = []
    var collectionLookupRequests: [String] = []
    var searchedAlbumQueries: [String] = []
    var albumQueryFilters: [AlbumQueryFilter] = []
    var searchedArtistQueries: [String] = []
    var searchedCollectionQueries: [String] = []
    var replaceLibraryCallCount = 0
    var replacedSnapshot: LibrarySnapshot?
    var replacedRefreshedAt: Date?
    var begunSyncRuns: [LibrarySyncRun] = []
    var upsertAlbumsCalls: [([Album], LibrarySyncRun)] = []
    var upsertTracksCalls: [([Track], LibrarySyncRun)] = []
    var replaceArtistsCalls: [([Artist], LibrarySyncRun)] = []
    var replaceCollectionsCalls: [([Collection], LibrarySyncRun)] = []
    var upsertPlaylistsCalls: [([LibraryPlaylistSnapshot], LibrarySyncRun)] = []
    var upsertPlaylistItemsCalls: [([LibraryPlaylistItemSnapshot], String, LibrarySyncRun)] = []
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
    var upsertAlbumError: LibraryError?
    var replaceTracksError: LibraryError?
    var beginIncrementalSyncError: LibraryError?
    var upsertAlbumsError: LibraryError?
    var upsertTracksError: LibraryError?
    var replaceArtistsError: LibraryError?
    var replaceCollectionsError: LibraryError?
    var upsertPlaylistsError: LibraryError?
    var upsertPlaylistItemsError: LibraryError?
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

    func upsertAlbum(_ album: Album) async throws {
        if let upsertAlbumError {
            throw upsertAlbumError
        }
        albumByID[album.plexID] = album
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

    func fetchTracks(forAlbum albumID: String) async throws -> [Track] {
        fetchTrackRequests.append(albumID)
        return tracksByAlbumID[albumID] ?? []
    }

    func track(id: String) async throws -> Track? {
        trackLookupRequests.append(id)
        return tracksByID[id]
    }

    func replaceTracks(_ tracks: [Track], forAlbum albumID: String) async throws {
        if let replaceTracksError {
            throw replaceTracksError
        }
        tracksByID = tracksByID.filter { $0.value.albumID != albumID }
        for track in tracks {
            tracksByID[track.plexID] = track
        }
        tracksByAlbumID = Dictionary(grouping: tracksByID.values, by: \.albumID)
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

    func fetchAlbumsByArtistName(_ artistName: String) async throws -> [Album] { [] }

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

    var collectionAlbumsByCollectionID: [String: [Album]] = [:]
    var collectionAlbumsRequests: [String] = []

    func collectionAlbums(collectionID: String) async throws -> [Album] {
        collectionAlbumsRequests.append(collectionID)
        return collectionAlbumsByCollectionID[collectionID] ?? []
    }

    func searchAlbums(query: String) async throws -> [Album] {
        searchedAlbumQueries.append(query)
        return searchedAlbumsByQuery[query] ?? []
    }

    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] {
        albumQueryFilters.append(filter)
        return queriedAlbumsByFilter[filter] ?? []
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

    func replaceArtists(_ artists: [Artist], in run: LibrarySyncRun) async throws {
        if let replaceArtistsError {
            throw replaceArtistsError
        }
        replaceArtistsCalls.append((artists, run))
        cachedArtists = artists
        artistsByID = Dictionary(uniqueKeysWithValues: artists.map { ($0.plexID, $0) })
    }

    func replaceCollections(_ collections: [Collection], in run: LibrarySyncRun) async throws {
        if let replaceCollectionsError {
            throw replaceCollectionsError
        }
        replaceCollectionsCalls.append((collections, run))
        cachedCollections = collections
        collectionsByID = Dictionary(uniqueKeysWithValues: collections.map { ($0.plexID, $0) })
    }

    func upsertAlbumCollections(_ albumCollectionIDs: [String: [String]], in run: LibrarySyncRun) async throws {
        // No-op for test double
    }

    func fetchPlaylists() async throws -> [LibraryPlaylistSnapshot] {
        fetchPlaylistsCalls += 1
        return cachedPlaylists
    }

    func fetchPlaylistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] {
        fetchPlaylistItemsRequests.append(playlistID)
        return cachedPlaylistItemsByPlaylistID[playlistID] ?? []
    }

    func upsertPlaylists(_ playlists: [LibraryPlaylistSnapshot], in run: LibrarySyncRun) async throws {
        if let upsertPlaylistsError {
            throw upsertPlaylistsError
        }
        upsertPlaylistsCalls.append((playlists, run))
        cachedPlaylists = playlists
    }

    func upsertPlaylistItems(
        _ items: [LibraryPlaylistItemSnapshot],
        playlistID: String,
        in run: LibrarySyncRun
    ) async throws {
        if let upsertPlaylistItemsError {
            throw upsertPlaylistItemsError
        }
        upsertPlaylistItemsCalls.append((items, playlistID, run))
        cachedPlaylistItemsByPlaylistID[playlistID] = items
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

    var markTracksWithValidAlbumsSeenCalls: [LibrarySyncRun] = []

    func markTracksWithValidAlbumsSeen(in run: LibrarySyncRun) async throws {
        markTracksWithValidAlbumsSeenCalls.append(run)
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

    var tagsByKind: [LibraryTagKind: [String]] = [:]
    var fetchTagsCalls: [LibraryTagKind] = []

    func fetchTags(kind: LibraryTagKind) async throws -> [String] {
        fetchTagsCalls.append(kind)
        return tagsByKind[kind] ?? []
    }
}
