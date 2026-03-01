import Foundation
import Testing
@testable import Lunara

@MainActor
struct LibraryStorePlaylistTests {

    // MARK: - Upsert

    @Test
    func upsertPlaylists_insertsNewPlaylistsCorrectly() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 9000))

        try await store.upsertPlaylists(
            [
                LibraryPlaylistSnapshot(plexID: "p1", title: "Chill Vibes", trackCount: 5, updatedAt: nil, thumbURL: nil),
                LibraryPlaylistSnapshot(plexID: "p2", title: "Workout Mix", trackCount: 10, updatedAt: nil, thumbURL: nil)
            ],
            in: run
        )

        let playlists = try await store.fetchPlaylists()
        #expect(playlists.count == 2)
        // Sorted by title ascending
        #expect(playlists[0].plexID == "p1")
        #expect(playlists[0].title == "Chill Vibes")
        #expect(playlists[0].trackCount == 5)
        #expect(playlists[1].plexID == "p2")
        #expect(playlists[1].title == "Workout Mix")
    }

    @Test
    func upsertPlaylists_updatesExistingPlaylistOnConflict() async throws {
        let store = try LibraryStore.inMemory()
        let run1 = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 9001))

        try await store.upsertPlaylists(
            [LibraryPlaylistSnapshot(plexID: "p1", title: "Old Title", trackCount: 3, updatedAt: nil, thumbURL: nil)],
            in: run1
        )

        let run2 = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 9002))

        try await store.upsertPlaylists(
            [LibraryPlaylistSnapshot(plexID: "p1", title: "New Title", trackCount: 7, updatedAt: nil, thumbURL: nil)],
            in: run2
        )
        _ = try await store.pruneRowsNotSeen(in: run2)

        let playlists = try await store.fetchPlaylists()
        #expect(playlists.count == 1)
        #expect(playlists[0].title == "New Title")
        #expect(playlists[0].trackCount == 7)
    }

    // MARK: - Playlist item order

    @Test
    func upsertPlaylistItems_preservesPositionOrderExactly() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 9010))

        try await store.upsertPlaylists(
            [LibraryPlaylistSnapshot(plexID: "p1", title: "Ordered", trackCount: 3, updatedAt: nil, thumbURL: nil)],
            in: run
        )
        try await store.upsertPlaylistItems(
            [
                LibraryPlaylistItemSnapshot(trackID: "track-c", position: 2, playlistItemID: nil),
                LibraryPlaylistItemSnapshot(trackID: "track-a", position: 0, playlistItemID: nil),
                LibraryPlaylistItemSnapshot(trackID: "track-b", position: 1, playlistItemID: nil)
            ],
            playlistID: "p1",
            in: run
        )

        let items = try await store.fetchPlaylistItems(playlistID: "p1")
        #expect(items.count == 3)
        // Results must be sorted by position regardless of insert order
        #expect(items[0].position == 0)
        #expect(items[0].trackID == "track-a")
        #expect(items[1].position == 1)
        #expect(items[1].trackID == "track-b")
        #expect(items[2].position == 2)
        #expect(items[2].trackID == "track-c")
    }

    @Test
    func upsertPlaylistItems_duplicateTrackIDsAtDifferentPositionsRemainDistinct() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 9020))

        try await store.upsertPlaylists(
            [LibraryPlaylistSnapshot(plexID: "p1", title: "Repeats", trackCount: 4, updatedAt: nil, thumbURL: nil)],
            in: run
        )
        // Same trackID appears at positions 0 and 2 — must remain as distinct rows
        try await store.upsertPlaylistItems(
            [
                LibraryPlaylistItemSnapshot(trackID: "track-repeat", position: 0, playlistItemID: nil),
                LibraryPlaylistItemSnapshot(trackID: "track-other", position: 1, playlistItemID: nil),
                LibraryPlaylistItemSnapshot(trackID: "track-repeat", position: 2, playlistItemID: nil),
                LibraryPlaylistItemSnapshot(trackID: "track-end", position: 3, playlistItemID: nil)
            ],
            playlistID: "p1",
            in: run
        )

        let items = try await store.fetchPlaylistItems(playlistID: "p1")
        #expect(items.count == 4)
        #expect(items[0].trackID == "track-repeat")
        #expect(items[0].position == 0)
        #expect(items[2].trackID == "track-repeat")
        #expect(items[2].position == 2)
        // Duplicate entries remain as distinct rows at different positions
        let repeatCount = items.filter { $0.trackID == "track-repeat" }.count
        #expect(repeatCount == 2)
    }

    // MARK: - Pruning

    @Test
    func pruneRowsNotSeen_removesStalePlaylistsAndTheirItems() async throws {
        let store = try LibraryStore.inMemory()
        let run1 = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 9030))

        try await store.upsertPlaylists(
            [
                LibraryPlaylistSnapshot(plexID: "p-keep", title: "Keep", trackCount: 2, updatedAt: nil, thumbURL: nil),
                LibraryPlaylistSnapshot(plexID: "p-remove", title: "Remove", trackCount: 1, updatedAt: nil, thumbURL: nil)
            ],
            in: run1
        )
        try await store.upsertPlaylistItems(
            [LibraryPlaylistItemSnapshot(trackID: "t1", position: 0, playlistItemID: nil)],
            playlistID: "p-keep",
            in: run1
        )
        try await store.upsertPlaylistItems(
            [LibraryPlaylistItemSnapshot(trackID: "t2", position: 0, playlistItemID: nil)],
            playlistID: "p-remove",
            in: run1
        )
        _ = try await store.pruneRowsNotSeen(in: run1)

        // Second run only sees "p-keep"
        let run2 = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 9031))
        try await store.upsertPlaylists(
            [LibraryPlaylistSnapshot(plexID: "p-keep", title: "Keep", trackCount: 2, updatedAt: nil, thumbURL: nil)],
            in: run2
        )
        try await store.upsertPlaylistItems(
            [LibraryPlaylistItemSnapshot(trackID: "t1", position: 0, playlistItemID: nil)],
            playlistID: "p-keep",
            in: run2
        )
        _ = try await store.pruneRowsNotSeen(in: run2)

        let playlists = try await store.fetchPlaylists()
        #expect(playlists.map(\.plexID) == ["p-keep"])

        let keptItems = try await store.fetchPlaylistItems(playlistID: "p-keep")
        #expect(keptItems.count == 1)

        let removedItems = try await store.fetchPlaylistItems(playlistID: "p-remove")
        #expect(removedItems.isEmpty)
    }

    @Test
    func pruneRowsNotSeen_playlistItemsOrphanedByPlaylistPruneAreAlsoCleaned() async throws {
        let store = try LibraryStore.inMemory()
        let run1 = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 9040))

        try await store.upsertPlaylists(
            [LibraryPlaylistSnapshot(plexID: "p-gone", title: "Gone", trackCount: 2, updatedAt: nil, thumbURL: nil)],
            in: run1
        )
        try await store.upsertPlaylistItems(
            [
                LibraryPlaylistItemSnapshot(trackID: "t1", position: 0, playlistItemID: nil),
                LibraryPlaylistItemSnapshot(trackID: "t2", position: 1, playlistItemID: nil)
            ],
            playlistID: "p-gone",
            in: run1
        )
        _ = try await store.pruneRowsNotSeen(in: run1)

        // Second run: playlist is gone
        let run2 = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 9041))
        _ = try await store.pruneRowsNotSeen(in: run2)

        let playlists = try await store.fetchPlaylists()
        #expect(playlists.isEmpty)

        // Items for the pruned playlist must not linger (no orphan rows)
        // fetchPlaylistItems returns [] for unknown or pruned playlist IDs
        let orphanItems = try await store.fetchPlaylistItems(playlistID: "p-gone")
        #expect(orphanItems.isEmpty)
    }

    // MARK: - Read API from cache

    @Test
    func fetchPlaylists_returnsEmptyWhenNoPersisted() async throws {
        let store = try LibraryStore.inMemory()
        let playlists = try await store.fetchPlaylists()
        #expect(playlists.isEmpty)
    }

    @Test
    func fetchPlaylistItems_returnsEmptyForUnknownPlaylistID() async throws {
        let store = try LibraryStore.inMemory()
        let items = try await store.fetchPlaylistItems(playlistID: "nonexistent")
        #expect(items.isEmpty)
    }

    @Test
    func fetchPlaylists_sortsByTitleAscending() async throws {
        let store = try LibraryStore.inMemory()
        let run = try await store.beginIncrementalSync(startedAt: Date(timeIntervalSince1970: 9050))

        try await store.upsertPlaylists(
            [
                LibraryPlaylistSnapshot(plexID: "p3", title: "Zen", trackCount: 1, updatedAt: nil, thumbURL: nil),
                LibraryPlaylistSnapshot(plexID: "p1", title: "Ambient", trackCount: 3, updatedAt: nil, thumbURL: nil),
                LibraryPlaylistSnapshot(plexID: "p2", title: "Metal", trackCount: 8, updatedAt: nil, thumbURL: nil)
            ],
            in: run
        )

        let playlists = try await store.fetchPlaylists()
        #expect(playlists.map(\.title) == ["Ambient", "Metal", "Zen"])
    }
}
