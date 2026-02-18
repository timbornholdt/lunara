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
    func album_whenCachedMetadataIsSparse_fetchesRemoteAlbumAndMergesMetadata() async throws {
        let subject = makeSubject()
        let sparseAlbum = makeAlbum(id: "album-1")
        subject.store.albumByID[sparseAlbum.plexID] = sparseAlbum
        subject.remote.albumsByID[sparseAlbum.plexID] = Album(
            plexID: sparseAlbum.plexID,
            title: sparseAlbum.title,
            artistName: sparseAlbum.artistName,
            year: sparseAlbum.year,
            thumbURL: sparseAlbum.thumbURL,
            genre: "Pop/Rock",
            rating: sparseAlbum.rating,
            addedAt: sparseAlbum.addedAt,
            trackCount: sparseAlbum.trackCount,
            duration: sparseAlbum.duration,
            review: "Detailed review",
            genres: ["Pop/Rock"],
            styles: ["Art Rock"],
            moods: ["Brooding"]
        )

        let mergedAlbum = try await subject.repo.album(id: sparseAlbum.plexID)

        #expect(subject.remote.fetchAlbumRequests == [sparseAlbum.plexID])
        #expect(mergedAlbum?.review == "Detailed review")
        #expect(mergedAlbum?.genres == ["Pop/Rock"])
        #expect(mergedAlbum?.styles == ["Art Rock"])
        #expect(mergedAlbum?.moods == ["Brooding"])
    }
    @Test
    func refreshLibrary_fetchesRemoteAlbumsAndTracks_thenPersistsIncrementalSync() async throws {
        let now = Date(timeIntervalSince1970: 12_345)
        let subject = makeSubject(now: now)
        let albumA = makeAlbum(id: "album-a", trackCount: 2)
        let albumB = makeAlbum(id: "album-b", trackCount: 1)
        subject.remote.albums = [albumA, albumB]
        subject.remote.tracksByAlbumID[albumA.plexID] = [
            makeTrack(id: "track-a1", albumID: albumA.plexID, number: 1)
        ]
        subject.remote.tracksByAlbumID[albumB.plexID] = [
            makeTrack(id: "track-b1", albumID: albumB.plexID, number: 1)
        ]
        subject.store.cachedArtists = [makeArtist(id: "artist-1")]
        subject.store.cachedCollections = [makeCollection(id: "collection-1")]
        let outcome = try await subject.repo.refreshLibrary(reason: .userInitiated)
        #expect(subject.remote.fetchAlbumsCallCount == 1)
        #expect(subject.remote.fetchTracksRequests == ["album-a", "album-b"])
        #expect(subject.store.replaceLibraryCallCount == 0)
        #expect(subject.store.begunSyncRuns.count == 1)
        #expect(subject.store.upsertAlbumsCalls.count == 1)
        #expect(subject.store.upsertTracksCalls.count == 1)
        #expect(subject.store.markAlbumsSeenCalls.count == 1)
        #expect(subject.store.markTracksSeenCalls.count == 1)
        #expect(subject.store.pruneRowsNotSeenCalls.count == 1)
        #expect(subject.store.completeIncrementalSyncCalls.count == 1)
        #expect(subject.store.upsertAlbumsCalls.first?.0.map(\.plexID) == ["album-a", "album-b"])
        #expect(subject.store.upsertTracksCalls.first?.0.map(\.plexID) == ["track-a1", "track-b1"])
        #expect(subject.store.completeIncrementalSyncCalls.first?.1 == now)
        #expect(outcome == LibraryRefreshOutcome(
            reason: .userInitiated,
            refreshedAt: now,
            albumCount: 2,
            trackCount: 2,
            artistCount: 1,
            collectionCount: 1
        ))
        await waitForArtworkRequests(
            on: subject.artworkPipeline,
            expectedOwnerIDs: ["album-a", "album-b"]
        )
        #expect(subject.artworkPipeline.thumbnailRequests.map(\.ownerID) == ["album-a", "album-b"])
    }
    @Test
    func refreshLibrary_whenArtworkPreloadFails_stillPersistsMetadataSnapshot() async throws {
        let subject = makeSubject()
        subject.remote.albums = [makeAlbum(id: "album-1")]
        subject.remote.tracksByAlbumID["album-1"] = [makeTrack(id: "track-1", albumID: "album-1", number: 1)]
        subject.artworkPipeline.fetchThumbnailError = .timeout
        let outcome = try await subject.repo.refreshLibrary(reason: .appLaunch)
        #expect(subject.store.completeIncrementalSyncCalls.count == 1)
        #expect(outcome.albumCount == 1)
    }
    @Test
    func refreshLibrary_withRelativeThumbnailPath_usesRemoteResolvedArtworkURL() async throws {
        let subject = makeSubject()
        let relativeThumb = "/library/metadata/96634/thumb/1769680528"
        let resolvedThumb = try #require(URL(string: "http://localhost:32400/library/metadata/96634/thumb/1769680528?X-Plex-Token=test"))
        subject.remote.albums = [makeAlbum(id: "album-1", thumbURL: relativeThumb)]
        subject.remote.artworkURLByRawValue[relativeThumb] = resolvedThumb
        subject.remote.tracksByAlbumID["album-1"] = [makeTrack(id: "track-1", albumID: "album-1", number: 1)]
        _ = try await subject.repo.refreshLibrary(reason: .appLaunch)
        await waitForArtworkRequests(on: subject.artworkPipeline, expectedOwnerIDs: ["album-1"])
        #expect(subject.remote.artworkURLRequests == [relativeThumb])
        #expect(subject.artworkPipeline.thumbnailRequests.first?.sourceURL == resolvedThumb)
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
        let upsertedAlbums = try #require(subject.store.upsertAlbumsCalls.first?.0)
        let upsertedTracks = try #require(subject.store.upsertTracksCalls.first?.0)
        #expect(upsertedAlbums.map(\.plexID) == ["album-a"])
        #expect(upsertedAlbums.first?.trackCount == 2)
        #expect(upsertedTracks.map(\.plexID) == ["track-a1", "track-b1"])
        #expect(upsertedTracks.map(\.albumID) == ["album-a", "album-a"])
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
        let firstCanonicalIDs = subject.store.upsertAlbumsCalls.first?.0.map(\.plexID)
        subject.remote.albums = [splitAlbumB, splitAlbumA]
        _ = try await subject.repo.refreshLibrary(reason: .userInitiated)
        let secondCanonicalIDs = subject.store.upsertAlbumsCalls.last?.0.map(\.plexID)
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
        #expect(subject.store.begunSyncRuns.isEmpty)
    }
    @Test
    func refreshLibrary_whenStoreFails_propagatesErrorAndPreservesOriginalTypeWhenAvailable() async {
        let subject = makeSubject()
        subject.remote.albums = [makeAlbum(id: "album-1", trackCount: 1)]
        subject.remote.tracksByAlbumID["album-1"] = [makeTrack(id: "track-1", albumID: "album-1", number: 1)]
        subject.store.upsertAlbumsError = .databaseCorrupted
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
    func refreshLibrary_computesAndPersistsRowLevelReconciliationCategories() async throws {
        let subject = makeSubject(now: Date(timeIntervalSince1970: 8_000))
        func makeRollupAlbum(id: String, title: String) -> Album {
            Album(
                plexID: id,
                title: title,
                artistName: "Artist",
                year: nil,
                thumbURL: nil,
                genre: nil,
                rating: nil,
                addedAt: nil,
                trackCount: 1,
                duration: 180
            )
        }

        let unchangedAlbum = makeRollupAlbum(id: "album-unchanged", title: "Same")
        let changedCachedAlbum = makeRollupAlbum(id: "album-changed", title: "Old")
        let deletedAlbum = makeRollupAlbum(id: "album-deleted", title: "Removed")
        subject.store.albumsByPage[1] = [unchangedAlbum, changedCachedAlbum, deletedAlbum]

        subject.store.tracksByAlbumID[unchangedAlbum.plexID] = [makeTrack(id: "track-unchanged", albumID: unchangedAlbum.plexID, number: 1)]
        subject.store.tracksByAlbumID[changedCachedAlbum.plexID] = [makeTrack(id: "track-changed", albumID: changedCachedAlbum.plexID, number: 1)]
        subject.store.tracksByAlbumID[deletedAlbum.plexID] = [makeTrack(id: "track-deleted", albumID: deletedAlbum.plexID, number: 1)]

        let changedRemoteAlbum = makeRollupAlbum(id: "album-changed", title: "New")
        let newAlbum = makeRollupAlbum(id: "album-new", title: "Brand New")
        subject.remote.albums = [unchangedAlbum, changedRemoteAlbum, newAlbum]
        subject.remote.tracksByAlbumID[unchangedAlbum.plexID] = [makeTrack(id: "track-unchanged", albumID: unchangedAlbum.plexID, number: 1)]
        subject.remote.tracksByAlbumID[changedRemoteAlbum.plexID] = [makeTrack(id: "track-changed", albumID: changedRemoteAlbum.plexID, number: 2)]
        subject.remote.tracksByAlbumID[newAlbum.plexID] = [makeTrack(id: "track-new", albumID: newAlbum.plexID, number: 1)]

        _ = try await subject.repo.refreshLibrary(reason: .userInitiated)

        #expect(subject.store.syncCheckpointByKey["reconciliation.albums.new"]?.value == "1")
        #expect(subject.store.syncCheckpointByKey["reconciliation.albums.changed"]?.value == "1")
        #expect(subject.store.syncCheckpointByKey["reconciliation.albums.unchanged"]?.value == "1")
        #expect(subject.store.syncCheckpointByKey["reconciliation.albums.deleted"]?.value == "1")
        #expect(subject.store.syncCheckpointByKey["reconciliation.tracks.new"]?.value == "1")
        #expect(subject.store.syncCheckpointByKey["reconciliation.tracks.changed"]?.value == "1")
        #expect(subject.store.syncCheckpointByKey["reconciliation.tracks.unchanged"]?.value == "1")
        #expect(subject.store.syncCheckpointByKey["reconciliation.tracks.deleted"]?.value == "1")
    }
    @Test
    func tracks_prefersRemoteWhenStoreHasCachedTracks() async throws {
        let subject = makeSubject()
        subject.store.tracksByAlbumID["album-7"] = [makeTrack(id: "track-7", albumID: "album-7", number: 1)]
        subject.remote.tracksByAlbumID["album-7"] = [makeTrack(id: "track-7-remote", albumID: "album-7", number: 1)]
        let tracks = try await subject.repo.tracks(forAlbum: "album-7")
        #expect(tracks.map(\.plexID) == ["track-7-remote"])
        #expect(subject.store.fetchTrackRequests == ["album-7"])
        #expect(subject.remote.fetchTracksRequests == ["album-7"])
    }
    @Test
    func tracks_whenStoreHasNoTracks_fetchesFromRemote() async throws {
        let subject = makeSubject()
        subject.remote.tracksByAlbumID["album-9"] = [makeTrack(id: "track-9", albumID: "album-9", number: 1)]
        let tracks = try await subject.repo.tracks(forAlbum: "album-9")
        #expect(tracks.map(\.plexID) == ["track-9"])
        #expect(subject.store.fetchTrackRequests == ["album-9"])
        #expect(subject.remote.fetchTracksRequests == ["album-9"])
    }
    @Test
    func tracks_whenRemoteFailsAndStoreHasCachedTracks_returnsCachedTracks() async throws {
        let subject = makeSubject()
        subject.store.tracksByAlbumID["album-8"] = [makeTrack(id: "track-8-cached", albumID: "album-8", number: 1)]
        subject.remote.fetchTracksErrorByAlbumID["album-8"] = .timeout

        let tracks = try await subject.repo.tracks(forAlbum: "album-8")

        #expect(tracks.map(\.plexID) == ["track-8-cached"])
        #expect(subject.store.fetchTrackRequests == ["album-8"])
        #expect(subject.remote.fetchTracksRequests == ["album-8"])
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
        store: LibraryStoreMock,
        artworkPipeline: ArtworkPipelineMock
    ) {
        let remote = LibraryRemoteMock()
        let store = LibraryStoreMock()
        let artworkPipeline = ArtworkPipelineMock()
        let repo = LibraryRepo(remote: remote, store: store, artworkPipeline: artworkPipeline, nowProvider: { now })
        return (repo, remote, store, artworkPipeline)
    }
    private func makeAlbum(
        id: String,
        title: String? = nil,
        artistName: String? = nil,
        year: Int? = nil,
        thumbURL: String? = nil,
        trackCount: Int = 0
    ) -> Album {
        Album(
            plexID: id,
            title: title ?? "Album \(id)",
            artistName: artistName ?? "Artist",
            year: year,
            thumbURL: thumbURL,
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
    private func waitForArtworkRequests(
        on pipeline: ArtworkPipelineMock,
        expectedOwnerIDs: [String]
    ) async {
        for _ in 0..<50 {
            if pipeline.thumbnailRequests.map(\.ownerID) == expectedOwnerIDs {
                return
            }
            await Task.yield()
        }
    }
}
