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
    func album_whenCached_returnsCachedWithoutRemoteFetch() async throws {
        let subject = makeSubject()
        let cachedAlbum = makeAlbum(id: "album-1")
        subject.store.albumByID[cachedAlbum.plexID] = cachedAlbum

        let loadedAlbum = try await subject.repo.album(id: cachedAlbum.plexID)

        #expect(loadedAlbum?.plexID == cachedAlbum.plexID)
        #expect(subject.remote.fetchAlbumRequests.isEmpty)
    }

    @Test
    func album_whenCacheMiss_fetchesRemoteAndPersistsAlbum() async throws {
        let subject = makeSubject()
        let remoteAlbum = makeAlbum(id: "album-remote")
        subject.remote.albumsByID[remoteAlbum.plexID] = remoteAlbum

        let loadedAlbum = try await subject.repo.album(id: remoteAlbum.plexID)

        #expect(loadedAlbum?.plexID == remoteAlbum.plexID)
        #expect(subject.remote.fetchAlbumRequests == [remoteAlbum.plexID])
        #expect(subject.store.albumByID[remoteAlbum.plexID]?.plexID == remoteAlbum.plexID)
    }

    @Test
    func searchAlbums_delegatesToStoreQueryService() async throws {
        let subject = makeSubject()
        subject.store.searchedAlbumsByQuery["miles"] = [makeAlbum(id: "album-1")]

        let albums = try await subject.repo.searchAlbums(query: "miles")

        #expect(subject.store.searchedAlbumQueries == ["miles"])
        #expect(albums.map(\.plexID) == ["album-1"])
    }

    @Test
    func queryAlbums_delegatesToStoreFlexibleQueryService() async throws {
        let subject = makeSubject()
        let filter = AlbumQueryFilter(textQuery: "miles", genreTags: ["Jazz"])
        subject.store.queriedAlbumsByFilter[filter] = [makeAlbum(id: "album-2")]

        let albums = try await subject.repo.queryAlbums(filter: filter)

        #expect(subject.store.albumQueryFilters == [filter])
        #expect(albums.map(\.plexID) == ["album-2"])
    }

    @Test
    func searchArtists_delegatesToStoreQueryService() async throws {
        let subject = makeSubject()
        subject.store.searchedArtistsByQuery["coltrane"] = [makeArtist(id: "artist-1")]

        let artists = try await subject.repo.searchArtists(query: "coltrane")

        #expect(subject.store.searchedArtistQueries == ["coltrane"])
        #expect(artists.map(\.plexID) == ["artist-1"])
    }

    @Test
    func searchCollections_delegatesToStoreQueryService() async throws {
        let subject = makeSubject()
        subject.store.searchedCollectionsByQuery["jazz"] = [makeCollection(id: "collection-1")]

        let collections = try await subject.repo.searchCollections(query: "jazz")

        #expect(subject.store.searchedCollectionQueries == ["jazz"])
        #expect(collections.map(\.plexID) == ["collection-1"])
    }

    @Test
    func track_delegatesToStoreLookup() async throws {
        let subject = makeSubject()
        let track = makeTrack(id: "track-1", albumID: "album-1", number: 1)
        subject.store.tracksByID[track.plexID] = track

        let loadedTrack = try await subject.repo.track(id: "track-1")

        #expect(subject.store.trackLookupRequests == ["track-1"])
        #expect(subject.remote.fetchTrackRequests.isEmpty)
        #expect(loadedTrack?.plexID == "track-1")
    }

    @Test
    func track_whenCacheMiss_fetchesFromRemote() async throws {
        let subject = makeSubject()
        let remoteTrack = makeTrack(id: "track-remote", albumID: "album-remote", number: 1)
        subject.remote.tracksByID[remoteTrack.plexID] = remoteTrack

        let loadedTrack = try await subject.repo.track(id: remoteTrack.plexID)

        #expect(subject.store.trackLookupRequests == [remoteTrack.plexID])
        #expect(subject.remote.fetchTrackRequests == [remoteTrack.plexID])
        #expect(loadedTrack?.plexID == remoteTrack.plexID)
        #expect(loadedTrack?.albumID == remoteTrack.albumID)
    }

    @Test
    func track_whenCacheMissAndRemoteReturnsNil_returnsNil() async throws {
        let subject = makeSubject()

        let loadedTrack = try await subject.repo.track(id: "missing-track")

        #expect(subject.store.trackLookupRequests == ["missing-track"])
        #expect(subject.remote.fetchTrackRequests == ["missing-track"])
        #expect(loadedTrack == nil)
    }

    @Test
    func track_whenCacheMissAndRemoteThrows_propagatesError() async {
        let subject = makeSubject()
        subject.remote.fetchTrackErrorByID["track-error"] = .timeout

        do {
            _ = try await subject.repo.track(id: "track-error")
            Issue.record("Expected track(id:) to throw")
        } catch let error as LibraryError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }

        #expect(subject.store.trackLookupRequests == ["track-error"])
        #expect(subject.remote.fetchTrackRequests == ["track-error"])
    }

    @Test
    func collection_delegatesToStoreLookup() async throws {
        let subject = makeSubject()
        let collection = makeCollection(id: "collection-1")
        subject.store.collectionsByID[collection.plexID] = collection

        let loadedCollection = try await subject.repo.collection(id: "collection-1")

        #expect(subject.store.collectionLookupRequests == ["collection-1"])
        #expect(loadedCollection?.plexID == "collection-1")
    }

    @Test
    func refreshLibrary_fetchesRemoteAlbumsAndTracks_thenPersistsIncrementalSync() async throws {
        let now = Date(timeIntervalSince1970: 12_345)
        let subject = makeSubject(now: now)
        let albumA = makeAlbum(id: "album-a", trackCount: 2)
        let albumB = makeAlbum(id: "album-b", trackCount: 1)
        subject.remote.albums = [albumA, albumB]
        subject.remote.artists = [makeArtist(id: "artist-a"), makeArtist(id: "artist-b")]
        subject.remote.collections = [makeCollection(id: "collection-a")]
        subject.remote.playlists = [
            LibraryRemotePlaylist(plexID: "playlist-1", title: "Playlist", trackCount: 2, updatedAt: nil)
        ]
        subject.remote.playlistItemsByPlaylistID["playlist-1"] = [
            LibraryRemotePlaylistItem(trackID: "track-a1", position: 0),
            LibraryRemotePlaylistItem(trackID: "track-b1", position: 1)
        ]
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
        #expect(subject.remote.fetchArtistsCallCount == 1)
        #expect(subject.remote.fetchCollectionsCallCount == 1)
        #expect(subject.remote.fetchPlaylistsCallCount == 1)
        #expect(subject.remote.fetchPlaylistItemsRequests == ["playlist-1"])
        #expect(subject.remote.fetchTracksRequests == ["album-a", "album-b"])
        #expect(subject.store.replaceLibraryCallCount == 0)
        #expect(subject.store.begunSyncRuns.count == 1)
        #expect(subject.store.upsertAlbumsCalls.count == 1)
        #expect(subject.store.upsertTracksCalls.count == 1)
        #expect(subject.store.replaceArtistsCalls.count == 1)
        #expect(subject.store.replaceCollectionsCalls.count == 1)
        #expect(subject.store.upsertPlaylistsCalls.count == 1)
        #expect(subject.store.upsertPlaylistItemsCalls.count == 1)
        #expect(subject.store.markAlbumsSeenCalls.count == 1)
        #expect(subject.store.markTracksSeenCalls.count == 1)
        #expect(subject.store.pruneRowsNotSeenCalls.count == 1)
        #expect(subject.store.completeIncrementalSyncCalls.count == 1)
        #expect(subject.store.upsertAlbumsCalls.first?.0.map(\.plexID) == ["album-a", "album-b"])
        #expect(subject.store.upsertTracksCalls.first?.0.map(\.plexID) == ["track-a1", "track-b1"])
        #expect(subject.store.replaceArtistsCalls.first?.0.map(\.plexID) == ["artist-a", "artist-b"])
        #expect(subject.store.replaceCollectionsCalls.first?.0.map(\.plexID) == ["collection-a"])
        #expect(subject.store.upsertPlaylistsCalls.first?.0.map(\.plexID) == ["playlist-1"])
        #expect(subject.store.upsertPlaylistItemsCalls.first?.1 == "playlist-1")
        #expect(subject.store.upsertPlaylistItemsCalls.first?.0.map(\.trackID) == ["track-a1", "track-b1"])
        #expect(subject.store.completeIncrementalSyncCalls.first?.1 == now)
        #expect(outcome == LibraryRefreshOutcome(
            reason: .userInitiated,
            refreshedAt: now,
            albumCount: 2,
            trackCount: 2,
            artistCount: 2,
            collectionCount: 1
        ))
        await waitForArtworkRequests(on: subject.artworkPipeline, expectedOwnerIDs: [])
        #expect(subject.artworkPipeline.thumbnailRequests.isEmpty)
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
        subject.remote.artists = [makeArtist(id: "artist-1")]
        subject.remote.collections = [makeCollection(id: "collection-1")]
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
    func refreshLibrary_whenArtistReplacementFails_propagatesError() async {
        let subject = makeSubject()
        subject.remote.albums = [makeAlbum(id: "album-1", trackCount: 1)]
        subject.remote.tracksByAlbumID["album-1"] = [makeTrack(id: "track-1", albumID: "album-1", number: 1)]
        subject.remote.artists = [makeArtist(id: "artist-1")]
        subject.remote.collections = [makeCollection(id: "collection-1")]
        subject.store.replaceArtistsError = .databaseCorrupted

        do {
            _ = try await subject.repo.refreshLibrary(reason: .userInitiated)
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
    func refreshLibrary_withUnchangedThumbAndExistingCachedFile_doesNotInvalidateOrRefetchArtwork() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-1", thumbURL: "/library/metadata/1/thumb/1", trackCount: 1)
        subject.store.albumsByPage[1] = [album]
        subject.store.tracksByAlbumID[album.plexID] = [makeTrack(id: "track-1", albumID: album.plexID, number: 1)]
        subject.remote.albums = [album]
        subject.remote.tracksByAlbumID[album.plexID] = [makeTrack(id: "track-1", albumID: album.plexID, number: 1)]

        let cachedPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-repo-artwork-\(UUID().uuidString).jpg")
        try Data("cached".utf8).write(to: cachedPath)
        subject.store.artworkPathByKey[ArtworkKey(ownerID: album.plexID, ownerType: .album, variant: .thumbnail)] = cachedPath.path

        _ = try await subject.repo.refreshLibrary(reason: .userInitiated)
        await waitForArtworkRequests(on: subject.artworkPipeline, expectedOwnerIDs: [])

        #expect(subject.artworkPipeline.thumbnailRequests.isEmpty)
        #expect(subject.artworkPipeline.invalidatedOwners.isEmpty)
    }

    @Test
    func refreshLibrary_withChangedThumbURL_invalidatesAndRefetchesArtwork() async throws {
        let subject = makeSubject()
        let cachedAlbum = makeAlbum(id: "album-2", thumbURL: "/library/metadata/2/thumb/old", trackCount: 1)
        let refreshedAlbum = makeAlbum(id: "album-2", thumbURL: "/library/metadata/2/thumb/new", trackCount: 1)
        subject.store.albumsByPage[1] = [cachedAlbum]
        subject.store.tracksByAlbumID[cachedAlbum.plexID] = [makeTrack(id: "track-2", albumID: cachedAlbum.plexID, number: 1)]
        subject.remote.albums = [refreshedAlbum]
        subject.remote.tracksByAlbumID[refreshedAlbum.plexID] = [makeTrack(id: "track-2", albumID: refreshedAlbum.plexID, number: 1)]

        let resolved = try #require(URL(string: "http://localhost:32400/library/metadata/2/thumb/new?X-Plex-Token=test"))
        let refreshedThumb = try #require(refreshedAlbum.thumbURL)
        subject.remote.artworkURLByRawValue[refreshedThumb] = resolved

        _ = try await subject.repo.refreshLibrary(reason: .userInitiated)
        await waitForArtworkRequests(on: subject.artworkPipeline, expectedOwnerIDs: [refreshedAlbum.plexID])

        #expect(subject.artworkPipeline.invalidatedOwners == [
            ArtworkPipelineMock.InvalidateOwnerRequest(ownerID: refreshedAlbum.plexID, ownerKind: .album)
        ])
        #expect(subject.artworkPipeline.thumbnailRequests.first?.sourceURL == resolved)
    }

    @Test
    func refreshLibrary_whenAlbumPruned_invalidatesAlbumArtworkCache() async throws {
        let subject = makeSubject()
        let activeAlbum = makeAlbum(id: "album-active", thumbURL: "/library/metadata/active/thumb", trackCount: 1)
        subject.remote.albums = [activeAlbum]
        subject.remote.tracksByAlbumID[activeAlbum.plexID] = [makeTrack(id: "track-active", albumID: activeAlbum.plexID, number: 1)]
        subject.store.pruneResult = LibrarySyncPruneResult(
            prunedAlbumIDs: ["album-deleted"],
            prunedTrackIDs: ["track-deleted"]
        )

        _ = try await subject.repo.refreshLibrary(reason: .userInitiated)
        await waitForArtworkRequests(on: subject.artworkPipeline, expectedOwnerIDs: [activeAlbum.plexID])

        #expect(subject.artworkPipeline.invalidatedOwners.contains(
            ArtworkPipelineMock.InvalidateOwnerRequest(ownerID: "album-deleted", ownerKind: .album)
        ))
    }
    @Test
    func tracks_whenStoreHasCachedTracks_returnsCachedWithoutRemoteFetch() async throws {
        let subject = makeSubject()
        subject.store.tracksByAlbumID["album-7"] = [makeTrack(id: "track-7", albumID: "album-7", number: 1)]
        subject.remote.tracksByAlbumID["album-7"] = [makeTrack(id: "track-7-remote", albumID: "album-7", number: 1)]
        let tracks = try await subject.repo.tracks(forAlbum: "album-7")
        #expect(tracks.map(\.plexID) == ["track-7"])
        #expect(subject.store.fetchTrackRequests == ["album-7"])
        #expect(subject.remote.fetchTracksRequests.isEmpty)
    }
    @Test
    func tracks_whenStoreHasNoTracks_fetchesFromRemote() async throws {
        let subject = makeSubject()
        subject.remote.tracksByAlbumID["album-9"] = [makeTrack(id: "track-9", albumID: "album-9", number: 1)]
        let tracks = try await subject.repo.tracks(forAlbum: "album-9")
        #expect(tracks.map(\.plexID) == ["track-9"])
        #expect(subject.store.fetchTrackRequests == ["album-9"])
        #expect(subject.remote.fetchTracksRequests == ["album-9"])
        #expect(subject.store.tracksByAlbumID["album-9"]?.map(\.plexID) == ["track-9"])
    }
    @Test
    func tracks_whenStoreHasCachedTracksAndRemoteWouldFail_stillReturnsCachedTracks() async throws {
        let subject = makeSubject()
        subject.store.tracksByAlbumID["album-8"] = [makeTrack(id: "track-8-cached", albumID: "album-8", number: 1)]
        subject.remote.fetchTracksErrorByAlbumID["album-8"] = .timeout

        let tracks = try await subject.repo.tracks(forAlbum: "album-8")

        #expect(tracks.map(\.plexID) == ["track-8-cached"])
        #expect(subject.store.fetchTrackRequests == ["album-8"])
        #expect(subject.remote.fetchTracksRequests.isEmpty)
    }

    @Test
    func refreshAlbumDetail_fetchesRemoteAlbumAndTracks_persistsAndReturnsOutcome() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-detail")
        let tracks = [makeTrack(id: "track-detail", albumID: album.plexID, number: 1)]
        subject.remote.albumsByID[album.plexID] = album
        subject.remote.tracksByAlbumID[album.plexID] = tracks

        let outcome = try await subject.repo.refreshAlbumDetail(albumID: album.plexID)

        #expect(subject.remote.fetchAlbumRequests == [album.plexID])
        #expect(subject.remote.fetchTracksRequests == [album.plexID])
        #expect(outcome.album?.plexID == album.plexID)
        #expect(outcome.tracks.map(\.plexID) == ["track-detail"])
        #expect(subject.store.albumByID[album.plexID]?.plexID == album.plexID)
        #expect(subject.store.tracksByAlbumID[album.plexID]?.map(\.plexID) == ["track-detail"])
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
