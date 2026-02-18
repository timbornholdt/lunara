import Foundation
import Testing
@testable import Lunara

struct LibraryStoreProtocolTests {
    @Test
    func libraryPage_clampsInvalidInputsToMinimumValues() {
        let page = LibraryPage(number: 0, size: 0)

        #expect(page.number == 1)
        #expect(page.size == 1)
        #expect(page.offset == 0)
    }

    @Test
    func libraryPage_computesOffsetUsingOneBasedPageNumbers() {
        let page = LibraryPage(number: 3, size: 50)

        #expect(page.offset == 100)
    }

    @Test
    func librarySnapshot_isEmptyOnlyWhenAllCollectionsAreEmpty() {
        let empty = LibrarySnapshot(albums: [], tracks: [], artists: [], collections: [])
        let populated = LibrarySnapshot(
            albums: [makeAlbum(id: "album-1")],
            tracks: [],
            artists: [],
            collections: []
        )

        #expect(empty.isEmpty)
        #expect(!populated.isEmpty)
    }

    @Test
    func librarySnapshot_tracksForAlbum_filtersByAlbumAndSortsByTrackNumber() {
        let snapshot = LibrarySnapshot(
            albums: [],
            tracks: [
                makeTrack(id: "track-2", albumID: "album-a", trackNumber: 2),
                makeTrack(id: "track-1", albumID: "album-a", trackNumber: 1),
                makeTrack(id: "track-9", albumID: "album-b", trackNumber: 9)
            ],
            artists: [],
            collections: []
        )

        let albumTracks = snapshot.tracks(forAlbumID: "album-a")

        #expect(albumTracks.map(\.plexID) == ["track-1", "track-2"])
    }

    @Test
    func librarySyncRun_init_setsStableIDAndStartTimestamp() {
        let start = Date(timeIntervalSince1970: 1234)
        let run = LibrarySyncRun(id: "sync-1", startedAt: start)

        #expect(run.id == "sync-1")
        #expect(run.startedAt == start)
    }

    @Test
    func librarySyncPruneResult_isEmptyOnlyWhenNoAlbumsOrTracksWerePruned() {
        let empty = LibrarySyncPruneResult.empty
        let prunedTracksOnly = LibrarySyncPruneResult(prunedAlbumIDs: [], prunedTrackIDs: ["track-1"])

        #expect(empty.isEmpty)
        #expect(!prunedTracksOnly.isEmpty)
    }

    @Test
    func librarySyncCheckpoint_preservesKeyValueAndTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 2222)
        let checkpoint = LibrarySyncCheckpoint(
            key: "albums.lastSeenCursor",
            value: "cursor-42",
            updatedAt: timestamp
        )

        #expect(checkpoint.key == "albums.lastSeenCursor")
        #expect(checkpoint.value == "cursor-42")
        #expect(checkpoint.updatedAt == timestamp)
    }

    private func makeAlbum(id: String) -> Album {
        Album(
            plexID: id,
            title: "Album \(id)",
            artistName: "Artist",
            year: 2020,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 0,
            duration: 0
        )
    }

    private func makeTrack(id: String, albumID: String, trackNumber: Int) -> Track {
        Track(
            plexID: id,
            albumID: albumID,
            title: "Track \(id)",
            trackNumber: trackNumber,
            duration: 180,
            artistName: "Artist",
            key: "/library/metadata/\(id)",
            thumbURL: nil
        )
    }
}
