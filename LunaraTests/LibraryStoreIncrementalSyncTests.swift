import Foundation
import Testing
@testable import Lunara

struct LibraryStoreIncrementalSyncTests {
    @Test
    func upsertAlbums_insertsAndUpdatesByPlexID() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5000))

        try await store.upsertAlbums([makeAlbum(id: "album-1", title: "Original")], in: run)
        try await store.upsertAlbums([makeAlbum(id: "album-1", title: "Updated")], in: run)

        let stored = try #require(try await store.fetchAlbum(id: "album-1"))
        #expect(stored.title == "Updated")
    }

    @Test
    func upsertTracks_whenBatchContainsForeignKeyViolation_rollsBackEntireBatch() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5100))
        try await store.upsertAlbums([makeAlbum(id: "album-1", title: "Album")], in: run)

        do {
            try await store.upsertTracks(
                [
                    makeTrack(id: "track-valid", albumID: "album-1", number: 1),
                    makeTrack(id: "track-invalid", albumID: "missing", number: 2)
                ],
                in: run
            )
            Issue.record("Expected upsertTracks to throw")
        } catch { }

        #expect(try await store.fetchTracks(forAlbum: "album-1").isEmpty)
    }

    @Test
    func markSeenAndPrune_removesUnseenRowsAndKeepsSeenRows() async throws {
        let store = try LibraryStore.inMemory()
        try await store.replaceLibrary(
            with: LibrarySnapshot(
                albums: [
                    makeAlbum(id: "album-keep", title: "Keep"),
                    makeAlbum(id: "album-drop", title: "Drop")
                ],
                tracks: [
                    makeTrack(id: "track-keep", albumID: "album-keep", number: 1),
                    makeTrack(id: "track-unseen", albumID: "album-keep", number: 2),
                    makeTrack(id: "track-drop", albumID: "album-drop", number: 1)
                ],
                artists: [],
                collections: []
            ),
            refreshedAt: Date(timeIntervalSince1970: 5200)
        )

        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5201))
        try await store.markAlbumsSeen(["album-keep"], in: run)
        try await store.markTracksSeen(["track-keep"], in: run)
        let result = try await store.pruneRowsNotSeen(in: run)

        #expect(result.prunedAlbumIDs == ["album-drop"])
        #expect(Set(result.prunedTrackIDs) == Set(["track-drop", "track-unseen"]))
        #expect(try await store.fetchAlbum(id: "album-keep") != nil)
        #expect(try await store.fetchTracks(forAlbum: "album-keep").map(\.plexID) == ["track-keep"])
    }

    @Test
    func checkpoint_roundTripsLatestValue() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5300))
        let first = LibrarySyncCheckpoint(key: "albums.cursor", value: "cursor-1", updatedAt: Date(timeIntervalSince1970: 5301))
        let second = LibrarySyncCheckpoint(key: "albums.cursor", value: "cursor-2", updatedAt: Date(timeIntervalSince1970: 5302))

        try await store.setSyncCheckpoint(first, in: run)
        try await store.setSyncCheckpoint(second, in: run)

        #expect(try await store.syncCheckpoint(forKey: "albums.cursor") == second)
    }

    @Test
    func replaceArtists_replacesExistingCatalogRows() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5310))

        try await store.replaceArtists(
            [
                Artist(plexID: "artist-old", name: "Old", sortName: nil, thumbURL: nil, genre: nil, summary: nil, albumCount: 1)
            ],
            in: run
        )

        try await store.replaceArtists(
            [
                Artist(plexID: "artist-new", name: "New", sortName: nil, thumbURL: nil, genre: nil, summary: nil, albumCount: 2)
            ],
            in: run
        )

        let artists = try await store.fetchArtists()
        #expect(artists.map(\.plexID) == ["artist-new"])
    }

    @Test
    func replaceCollections_replacesExistingCatalogRows() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5311))

        try await store.replaceCollections(
            [
                Collection(plexID: "collection-old", title: "Old", thumbURL: nil, summary: nil, albumCount: 1, updatedAt: nil)
            ],
            in: run
        )

        try await store.replaceCollections(
            [
                Collection(plexID: "collection-new", title: "New", thumbURL: nil, summary: nil, albumCount: 2, updatedAt: nil)
            ],
            in: run
        )

        let collections = try await store.fetchCollections()
        #expect(collections.map(\.plexID) == ["collection-new"])
    }

    @Test
    func completeIncrementalSync_setsLastRefreshDate() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5400))
        let refreshedAt = Date(timeIntervalSince1970: 5401)

        try await store.completeIncrementalSync(run, refreshedAt: refreshedAt)

        #expect(try await store.lastRefreshDate() == refreshedAt)
    }

    @Test
    func prune_preservesAlbumPagingOrderForRemainingRows() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5500))
        try await store.upsertAlbums(
            [
                makeAlbum(id: "album-c", title: "Gamma", artist: "Artist C"),
                makeAlbum(id: "album-a", title: "Alpha", artist: "Artist A"),
                makeAlbum(id: "album-b", title: "Beta", artist: "Artist B")
            ],
            in: run
        )
        try await store.markAlbumsSeen(["album-a", "album-b"], in: run)
        _ = try await store.pruneRowsNotSeen(in: run)

        let firstPage = try await store.fetchAlbums(page: LibraryPage(number: 1, size: 2))
        #expect(firstPage.map(\.plexID) == ["album-a", "album-b"])
    }

    @Test
    func prune_preservesTrackSortOrderForRemainingRows() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5600))
        try await store.upsertAlbums([makeAlbum(id: "album-1", title: "Album")], in: run)
        try await store.upsertTracks(
            [
                makeTrack(id: "track-2", albumID: "album-1", number: 2),
                makeTrack(id: "track-1", albumID: "album-1", number: 1)
            ],
            in: run
        )
        try await store.markAlbumsSeen(["album-1"], in: run)
        try await store.markTracksSeen(["track-1", "track-2"], in: run)
        _ = try await store.pruneRowsNotSeen(in: run)

        #expect(try await store.fetchTracks(forAlbum: "album-1").map(\.plexID) == ["track-1", "track-2"])
    }

    @Test
    func markSeen_withUnknownIDs_isNoOpInEmptyStore() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 5700))

        try await store.markAlbumsSeen(["missing-album"], in: run)
        try await store.markTracksSeen(["missing-track"], in: run)

        #expect(try await store.pruneRowsNotSeen(in: run).isEmpty)
    }

    @Test
    func checkpoint_canBeStoredWithoutRunAssociation() async throws {
        let store = try LibraryStore.inMemory()
        let checkpoint = LibrarySyncCheckpoint(
            key: "global.cursor",
            value: "value-1",
            updatedAt: Date(timeIntervalSince1970: 5800)
        )

        try await store.setSyncCheckpoint(checkpoint, in: nil)

        #expect(try await store.syncCheckpoint(forKey: "global.cursor") == checkpoint)
    }

    @Test
    func endToEnd_insertUpdatePruneCheckpointAndComplete() async throws {
        let store = try LibraryStore.inMemory()
        try await store.replaceLibrary(
            with: LibrarySnapshot(
                albums: [makeAlbum(id: "album-old", title: "Old")],
                tracks: [makeTrack(id: "track-old", albumID: "album-old", number: 1)],
                artists: [],
                collections: []
            ),
            refreshedAt: Date(timeIntervalSince1970: 6200)
        )

        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 6201))
        try await store.upsertAlbums([makeAlbum(id: "album-new", title: "New")], in: run)
        try await store.upsertTracks([makeTrack(id: "track-new", albumID: "album-new", number: 1)], in: run)
        try await store.markAlbumsSeen(["album-new"], in: run)
        try await store.markTracksSeen(["track-new"], in: run)
        let pruneResult = try await store.pruneRowsNotSeen(in: run)
        let checkpoint = LibrarySyncCheckpoint(
            key: "albums.cursor",
            value: "cursor-final",
            updatedAt: Date(timeIntervalSince1970: 6202)
        )
        try await store.setSyncCheckpoint(checkpoint, in: run)
        try await store.completeIncrementalSync(run, refreshedAt: Date(timeIntervalSince1970: 6203))

        #expect(pruneResult.prunedAlbumIDs == ["album-old"])
        #expect(pruneResult.prunedTrackIDs == ["track-old"])
        #expect(try await store.fetchAlbum(id: "album-new") != nil)
        #expect(try await store.syncCheckpoint(forKey: "albums.cursor") == checkpoint)
        #expect(try await store.lastRefreshDate() == Date(timeIntervalSince1970: 6203))
    }

    private func makeAlbum(id: String, title: String, artist: String = "Artist") -> Album {
        Album(
            plexID: id,
            title: title,
            artistName: artist,
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 0,
            duration: 0
        )
    }

    private func makeTrack(id: String, albumID: String, number: Int) -> Track {
        Track(
            plexID: id,
            albumID: albumID,
            title: "Track \(id)",
            trackNumber: number,
            duration: 100,
            artistName: "Artist",
            key: "/library/parts/\(id)/1/file.mp3",
            thumbURL: nil
        )
    }
}
