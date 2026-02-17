import Foundation
import Testing
@testable import Lunara

@MainActor
struct LibraryRepoTests {
    @Test
    func albums_readsFromStoreWithSamePageDescriptor() async throws {
        let subject = makeSubject()
        let expected = [makeAlbum(id: "album-1"), makeAlbum(id: "album-2")]
        subject.store.albumsByPage[1] = expected
        let page = LibraryPage(number: 1, size: 2)

        let actual = try await subject.repo.albums(page: page)

        #expect(actual == expected)
        #expect(subject.store.fetchAlbumsRequests == [page])
        #expect(subject.remote.fetchAlbumsCallCount == 0)
    }

    @Test
    func refreshLibrary_fetchesRemoteAlbumsAndTracks_thenReplacesStoreSnapshot() async throws {
        let now = Date(timeIntervalSince1970: 12_345)
        let subject = makeSubject(now: now)
        let albumA = makeAlbum(id: "album-a", trackCount: 2)
        let albumB = makeAlbum(id: "album-b", trackCount: 1)
        subject.remote.albums = [albumA, albumB]
        subject.remote.tracksByAlbumID[albumA.plexID] = [
            makeTrack(id: "track-a1", albumID: albumA.plexID, number: 1),
            makeTrack(id: "track-a2", albumID: albumA.plexID, number: 2)
        ]
        subject.remote.tracksByAlbumID[albumB.plexID] = [
            makeTrack(id: "track-b1", albumID: albumB.plexID, number: 1)
        ]
        subject.store.cachedArtists = [makeArtist(id: "artist-1")]
        subject.store.cachedCollections = [makeCollection(id: "collection-1")]

        let outcome = try await subject.repo.refreshLibrary(reason: .userInitiated)

        #expect(subject.remote.fetchAlbumsCallCount == 1)
        #expect(subject.remote.fetchTracksRequests == [albumA.plexID, albumB.plexID])
        #expect(subject.store.replaceLibraryCallCount == 1)
        #expect(subject.store.replacedSnapshot?.albums.map(\.plexID) == ["album-a", "album-b"])
        #expect(subject.store.replacedSnapshot?.tracks.map(\.plexID) == ["track-a1", "track-a2", "track-b1"])
        #expect(subject.store.replacedSnapshot?.artists.map(\.plexID) == ["artist-1"])
        #expect(subject.store.replacedSnapshot?.collections.map(\.plexID) == ["collection-1"])
        #expect(subject.store.replacedRefreshedAt == now)
        #expect(outcome == LibraryRefreshOutcome(
            reason: .userInitiated,
            refreshedAt: now,
            albumCount: 2,
            trackCount: 3,
            artistCount: 1,
            collectionCount: 1
        ))
    }

    @Test
    func refreshLibrary_withSplitAlbumGroups_mergesAlbumsAndRehomesTracksToCanonicalAlbum() async throws {
        let subject = makeSubject()
        let splitAlbumA = makeAlbum(id: "album-b", title: "Shared Album", artistName: "Shared Artist", year: 1999, trackCount: 1)
        let splitAlbumB = makeAlbum(id: "album-a", title: "Shared Album", artistName: "Shared Artist", year: 1999, trackCount: 1)
        subject.remote.albums = [splitAlbumA, splitAlbumB]
        subject.remote.tracksByAlbumID[splitAlbumA.plexID] = [
            makeTrack(id: "track-b1", albumID: splitAlbumA.plexID, number: 2)
        ]
        subject.remote.tracksByAlbumID[splitAlbumB.plexID] = [
            makeTrack(id: "track-a1", albumID: splitAlbumB.plexID, number: 1)
        ]

        let outcome = try await subject.repo.refreshLibrary(reason: .userInitiated)
        let persistedSnapshot = try #require(subject.store.replacedSnapshot)

        #expect(persistedSnapshot.albums.map(\.plexID) == ["album-a"])
        #expect(persistedSnapshot.albums.first?.trackCount == 2)
        #expect(persistedSnapshot.tracks.map(\.plexID) == ["track-a1", "track-b1"])
        #expect(persistedSnapshot.tracks.map(\.albumID) == ["album-a", "album-a"])
        #expect(outcome.albumCount == 1)
        #expect(outcome.trackCount == 2)
    }

    @Test
    func refreshLibrary_withDifferentRemoteOrder_keepsCanonicalAlbumSelectionStable() async throws {
        let subject = makeSubject()
        let splitAlbumA = makeAlbum(id: "album-b", title: "Shared Album", artistName: "Shared Artist", year: 1999, trackCount: 1)
        let splitAlbumB = makeAlbum(id: "album-a", title: "Shared Album", artistName: "Shared Artist", year: 1999, trackCount: 1)
        subject.remote.tracksByAlbumID[splitAlbumA.plexID] = [
            makeTrack(id: "track-b1", albumID: splitAlbumA.plexID, number: 2)
        ]
        subject.remote.tracksByAlbumID[splitAlbumB.plexID] = [
            makeTrack(id: "track-a1", albumID: splitAlbumB.plexID, number: 1)
        ]

        subject.remote.albums = [splitAlbumA, splitAlbumB]
        _ = try await subject.repo.refreshLibrary(reason: .appLaunch)
        let firstCanonicalIDs = subject.store.replacedSnapshot?.albums.map(\.plexID)

        subject.remote.albums = [splitAlbumB, splitAlbumA]
        _ = try await subject.repo.refreshLibrary(reason: .userInitiated)
        let secondCanonicalIDs = subject.store.replacedSnapshot?.albums.map(\.plexID)

        #expect(firstCanonicalIDs == ["album-a"])
        #expect(secondCanonicalIDs == ["album-a"])
    }

    @Test
    func refreshLibrary_whenRemoteFails_doesNotReplaceStoreAndPropagatesError() async {
        let subject = makeSubject()
        subject.remote.fetchAlbumsError = .timeout

        do {
            _ = try await subject.repo.refreshLibrary(reason: .appLaunch)
            Issue.record("Expected refreshLibrary to throw")
        } catch let error as LibraryError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }

        #expect(subject.store.replaceLibraryCallCount == 0)
    }

    @Test
    func refreshLibrary_whenStoreFails_propagatesErrorAndPreservesOriginalTypeWhenAvailable() async {
        let subject = makeSubject()
        subject.remote.albums = [makeAlbum(id: "album-1", trackCount: 1)]
        subject.remote.tracksByAlbumID["album-1"] = [makeTrack(id: "track-1", albumID: "album-1", number: 1)]
        subject.store.replaceLibraryError = .databaseCorrupted

        do {
            _ = try await subject.repo.refreshLibrary(reason: .appLaunch)
            Issue.record("Expected refreshLibrary to throw")
        } catch let error as LibraryError {
            #expect(error == .databaseCorrupted)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }
    }

    @Test
    func tracks_readsFromStore() async throws {
        let subject = makeSubject()
        subject.store.tracksByAlbumID["album-7"] = [makeTrack(id: "track-7", albumID: "album-7", number: 1)]

        let tracks = try await subject.repo.tracks(forAlbum: "album-7")

        #expect(tracks.map(\.plexID) == ["track-7"])
        #expect(subject.store.fetchTrackRequests == ["album-7"])
    }

    @Test
    func streamURL_delegatesToRemote() async throws {
        let subject = makeSubject()
        let track = makeTrack(id: "track-url", albumID: "album-1", number: 1)
        let url = try #require(URL(string: "https://example.com/stream.mp3"))
        subject.remote.streamURLByTrackID[track.plexID] = url

        let resolved = try await subject.repo.streamURL(for: track)

        #expect(resolved == url)
        #expect(subject.remote.streamURLRequests == [track.plexID])
    }

    @Test
    func streamURL_whenRemoteThrowsLibraryError_propagatesError() async {
        let subject = makeSubject()
        let track = makeTrack(id: "track-url", albumID: "album-1", number: 1)
        subject.remote.streamURLError = .authExpired

        do {
            _ = try await subject.repo.streamURL(for: track)
            Issue.record("Expected streamURL(for:) to throw")
        } catch let error as LibraryError {
            #expect(error == .authExpired)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }
    }

    @Test
    func lastRefreshDate_readsFromStore() async throws {
        let subject = makeSubject()
        let expectedDate = Date(timeIntervalSince1970: 9000)
        subject.store.lastRefresh = expectedDate

        let actualDate = try await subject.repo.lastRefreshDate()

        #expect(actualDate == expectedDate)
    }

    private func makeSubject(now: Date = Date(timeIntervalSince1970: 1000)) -> (
        repo: LibraryRepo,
        remote: LibraryRemoteMock,
        store: LibraryStoreMock
    ) {
        let remote = LibraryRemoteMock()
        let store = LibraryStoreMock()
        let repo = LibraryRepo(remote: remote, store: store, nowProvider: { now })
        return (repo, remote, store)
    }

    private func makeAlbum(
        id: String,
        title: String? = nil,
        artistName: String? = nil,
        year: Int? = nil,
        trackCount: Int = 0
    ) -> Album {
        Album(
            plexID: id,
            title: title ?? "Album \(id)",
            artistName: artistName ?? "Artist",
            year: year,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: trackCount,
            duration: 0
        )
    }

    private func makeTrack(id: String, albumID: String, number: Int) -> Track {
        Track(
            plexID: id,
            albumID: albumID,
            title: "Track \(id)",
            trackNumber: number,
            duration: 180,
            artistName: "Artist",
            key: "/library/parts/\(id)/1/file.mp3",
            thumbURL: nil
        )
    }

    private func makeArtist(id: String) -> Artist {
        Artist(
            plexID: id,
            name: "Artist \(id)",
            sortName: nil,
            thumbURL: nil,
            genre: nil,
            summary: nil,
            albumCount: 1
        )
    }

    private func makeCollection(id: String) -> Collection {
        Collection(
            plexID: id,
            title: "Collection \(id)",
            thumbURL: nil,
            summary: nil,
            albumCount: 1,
            updatedAt: nil
        )
    }
}
