import Foundation
import Testing
@testable import Lunara

@MainActor
struct ArtworkPipelineTests {
    @Test
    func fetchThumbnail_whenCachedFileExists_returnsFileWithoutNetworkFetch() async throws {
        let fixture = try Fixture()
        let key = ArtworkKey(ownerID: "album-1", ownerType: .album, variant: .thumbnail)
        let cachedURL = fixture.cacheDirectory.appendingPathComponent("cached-thumb.jpg")
        try Data("cached".utf8).write(to: cachedURL)
        fixture.store.artworkPathByKey[key] = cachedURL.path

        let result = try await fixture.pipeline.fetchThumbnail(
            for: "album-1",
            ownerKind: .album,
            sourceURL: URL(string: "https://plex.example.com/thumb.jpg")
        )

        #expect(result == cachedURL)
        #expect(fixture.session.requests.isEmpty)
        #expect(fixture.store.deletedArtworkKeys.isEmpty)
    }

    @Test
    func fetchFullSize_whenCacheMissing_fetchesPersistsAndReturnsLocalURL() async throws {
        let fixture = try Fixture()
        fixture.session.dataToReturn = Data("remote-image".utf8)

        let result = try await fixture.pipeline.fetchFullSize(
            for: "album-2",
            ownerKind: .album,
            sourceURL: URL(string: "https://plex.example.com/full.png")
        )

        let request = try #require(fixture.session.requests.first)
        #expect(request.url?.absoluteString == "https://plex.example.com/full.png")

        let stored = try #require(fixture.store.setArtworkPathCalls.first)
        #expect(stored.key == ArtworkKey(ownerID: "album-2", ownerType: .album, variant: .full))
        #expect(result?.path == stored.path)

        let persistedData = try Data(contentsOf: URL(fileURLWithPath: stored.path))
        #expect(persistedData == Data("remote-image".utf8))
    }

    @Test
    func fetchThumbnail_whenStoredPathIsStale_cleansStoreThenFetchesFreshFile() async throws {
        let fixture = try Fixture()
        let staleKey = ArtworkKey(ownerID: "album-3", ownerType: .album, variant: .thumbnail)
        fixture.store.artworkPathByKey[staleKey] = fixture.cacheDirectory.appendingPathComponent("missing.jpg").path
        fixture.session.dataToReturn = Data("fresh".utf8)

        _ = try await fixture.pipeline.fetchThumbnail(
            for: "album-3",
            ownerKind: .album,
            sourceURL: URL(string: "https://plex.example.com/thumb.webp")
        )

        #expect(fixture.store.deletedArtworkKeys.contains(staleKey))
        #expect(fixture.session.requests.count == 1)
        #expect(fixture.store.setArtworkPathCalls.count == 1)
    }

    @Test
    func fetchThumbnail_withoutSourceURLAndNoCache_returnsNil() async throws {
        let fixture = try Fixture()

        let result = try await fixture.pipeline.fetchThumbnail(
            for: "album-4",
            ownerKind: .album,
            sourceURL: nil
        )

        #expect(result == nil)
        #expect(fixture.session.requests.isEmpty)
        #expect(fixture.store.setArtworkPathCalls.isEmpty)
    }

    @Test
    func invalidateCache_forOwner_removesBothVariantsFromDiskAndStore() async throws {
        let fixture = try Fixture()
        let thumbKey = ArtworkKey(ownerID: "artist-1", ownerType: .artist, variant: .thumbnail)
        let fullKey = ArtworkKey(ownerID: "artist-1", ownerType: .artist, variant: .full)
        let thumbURL = fixture.cacheDirectory.appendingPathComponent("thumb.jpg")
        let fullURL = fixture.cacheDirectory.appendingPathComponent("full.jpg")

        try Data("thumb".utf8).write(to: thumbURL)
        try Data("full".utf8).write(to: fullURL)
        fixture.store.artworkPathByKey[thumbKey] = thumbURL.path
        fixture.store.artworkPathByKey[fullKey] = fullURL.path

        try await fixture.pipeline.invalidateCache(for: "artist-1", ownerKind: .artist)

        #expect(!FileManager.default.fileExists(atPath: thumbURL.path))
        #expect(!FileManager.default.fileExists(atPath: fullURL.path))
        #expect(fixture.store.deletedArtworkKeys.contains(thumbKey))
        #expect(fixture.store.deletedArtworkKeys.contains(fullKey))
    }

    @Test
    func invalidateAllCache_removesExistingFilesAndRecreatesDirectory() async throws {
        let fixture = try Fixture()
        let path = fixture.cacheDirectory.appendingPathComponent("anything.jpg")
        try Data("bytes".utf8).write(to: path)

        try await fixture.pipeline.invalidateAllCache()

        #expect(FileManager.default.fileExists(atPath: fixture.cacheDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    @Test
    func fetchThumbnail_whenRemoteTimesOut_throwsLibraryTimeout() async {
        do {
            let fixture = try Fixture()
            fixture.session.errorToThrow = URLError(.timedOut)

            _ = try await fixture.pipeline.fetchThumbnail(
                for: "album-timeout",
                ownerKind: .album,
                sourceURL: URL(string: "https://plex.example.com/thumb.jpg")
            )
            Issue.record("Expected timeout error")
        } catch let error as LibraryError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected LibraryError.timeout, got: \(error)")
        }
    }

    @Test
    func fetchFullSize_whenResponseStatusIs404_throwsResourceNotFound() async {
        do {
            let fixture = try Fixture()
            fixture.session.responseToReturn = HTTPURLResponse(
                url: URL(string: "https://plex.example.com/full.jpg")!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )

            _ = try await fixture.pipeline.fetchFullSize(
                for: "album-404",
                ownerKind: .album,
                sourceURL: URL(string: "https://plex.example.com/full.jpg")
            )
            Issue.record("Expected resourceNotFound error")
        } catch let error as LibraryError {
            #expect(error == .resourceNotFound(type: "artwork", id: "album-404"))
        } catch {
            Issue.record("Expected LibraryError.resourceNotFound, got: \(error)")
        }
    }

    @Test
    func fetches_withDifferentVariants_keepSeparateCachedFiles() async throws {
        let fixture = try Fixture()

        _ = try await fixture.pipeline.fetchThumbnail(
            for: "album-variant",
            ownerKind: .album,
            sourceURL: URL(string: "https://plex.example.com/art.jpg")
        )
        _ = try await fixture.pipeline.fetchFullSize(
            for: "album-variant",
            ownerKind: .album,
            sourceURL: URL(string: "https://plex.example.com/art.jpg")
        )

        let thumb = try #require(
            fixture.store.setArtworkPathCalls.first {
                $0.key == ArtworkKey(ownerID: "album-variant", ownerType: .album, variant: .thumbnail)
            }
        )
        let full = try #require(
            fixture.store.setArtworkPathCalls.first {
                $0.key == ArtworkKey(ownerID: "album-variant", ownerType: .album, variant: .full)
            }
        )

        #expect(thumb.path != full.path)
        #expect(FileManager.default.fileExists(atPath: thumb.path))
        #expect(FileManager.default.fileExists(atPath: full.path))
    }

    @Test
    func fetch_whenCacheExceedsLimit_evictsLeastRecentlyUsedFile() async throws {
        let fixture = try Fixture(maxCacheSizeBytes: 12)

        fixture.session.dataToReturn = Data("AAAAAA".utf8)
        _ = try await fixture.pipeline.fetchThumbnail(
            for: "album-a",
            ownerKind: .album,
            sourceURL: URL(string: "https://plex.example.com/a.jpg")
        )
        let pathA = try #require(
            fixture.store.setArtworkPathCalls.last {
                $0.key == ArtworkKey(ownerID: "album-a", ownerType: .album, variant: .thumbnail)
            }?.path
        )

        fixture.session.dataToReturn = Data("BBBBBB".utf8)
        _ = try await fixture.pipeline.fetchThumbnail(
            for: "album-b",
            ownerKind: .album,
            sourceURL: URL(string: "https://plex.example.com/b.jpg")
        )
        let pathB = try #require(
            fixture.store.setArtworkPathCalls.last {
                $0.key == ArtworkKey(ownerID: "album-b", ownerType: .album, variant: .thumbnail)
            }?.path
        )

        _ = try await fixture.pipeline.fetchThumbnail(
            for: "album-a",
            ownerKind: .album,
            sourceURL: URL(string: "https://plex.example.com/a.jpg")
        )

        fixture.session.dataToReturn = Data("CCCCCC".utf8)
        _ = try await fixture.pipeline.fetchThumbnail(
            for: "album-c",
            ownerKind: .album,
            sourceURL: URL(string: "https://plex.example.com/c.jpg")
        )
        let pathC = try #require(
            fixture.store.setArtworkPathCalls.last {
                $0.key == ArtworkKey(ownerID: "album-c", ownerType: .album, variant: .thumbnail)
            }?.path
        )

        #expect(FileManager.default.fileExists(atPath: pathA))
        #expect(!FileManager.default.fileExists(atPath: pathB))
        #expect(FileManager.default.fileExists(atPath: pathC))
    }

    @Test
    func fetch_whenCacheExceedsLimit_keepsTotalBytesUnderConfiguredCap() async throws {
        let fixture = try Fixture(maxCacheSizeBytes: 10)

        fixture.session.dataToReturn = Data("111111".utf8)
        _ = try await fixture.pipeline.fetchThumbnail(
            for: "cap-1",
            ownerKind: .album,
            sourceURL: URL(string: "https://plex.example.com/1.jpg")
        )

        fixture.session.dataToReturn = Data("222222".utf8)
        _ = try await fixture.pipeline.fetchThumbnail(
            for: "cap-2",
            ownerKind: .album,
            sourceURL: URL(string: "https://plex.example.com/2.jpg")
        )

        let urls = try FileManager.default.contentsOfDirectory(
            at: fixture.cacheDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )
        let totalBytes = try urls.reduce(0) { partial, url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                return partial
            }
            return partial + (values.fileSize ?? 0)
        }

        #expect(totalBytes <= 10)
    }
}

private final class ArtworkSessionMock: URLSessionProtocol {
    var dataToReturn = Data("image".utf8)
    var responseToReturn: URLResponse?
    var errorToThrow: Error?

    private(set) var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)

        if let errorToThrow {
            throw errorToThrow
        }

        let response = responseToReturn ?? HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (dataToReturn, response)
    }
}

@MainActor
private final class ArtworkStoreMock: LibraryStoreProtocol {
    struct SetArtworkPathCall: Equatable {
        let path: String
        let key: ArtworkKey
    }

    var artworkPathByKey: [ArtworkKey: String] = [:]
    private(set) var setArtworkPathCalls: [SetArtworkPathCall] = []
    private(set) var deletedArtworkKeys: [ArtworkKey] = []

    func fetchAlbums(page: LibraryPage) async throws -> [Album] { [] }
    func fetchAlbum(id: String) async throws -> Album? { nil }
    func upsertAlbum(_ album: Album) async throws { }
    func fetchTracks(forAlbum albumID: String) async throws -> [Track] { [] }
    func replaceTracks(_ tracks: [Track], forAlbum albumID: String) async throws { }
    func track(id: String) async throws -> Track? { nil }
    func fetchArtists() async throws -> [Artist] { [] }
    func fetchArtist(id: String) async throws -> Artist? { nil }
    func fetchAlbumsByArtistName(_ artistName: String) async throws -> [Album] { [] }
    func fetchCollections() async throws -> [Collection] { [] }
    func collection(id: String) async throws -> Collection? { nil }
    func searchAlbums(query: String) async throws -> [Album] { [] }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] { [] }
    func searchArtists(query: String) async throws -> [Artist] { [] }
    func searchCollections(query: String) async throws -> [Collection] { [] }
    func replaceLibrary(with snapshot: LibrarySnapshot, refreshedAt: Date) async throws { }
    func lastRefreshDate() async throws -> Date? { nil }
    func beginIncrementalSync(startedAt: Date) async throws -> LibrarySyncRun {
        LibrarySyncRun(id: "artwork-store-sync", startedAt: startedAt)
    }
    func upsertAlbums(_ albums: [Album], in run: LibrarySyncRun) async throws { }
    func upsertTracks(_ tracks: [Track], in run: LibrarySyncRun) async throws { }
    func replaceArtists(_ artists: [Artist], in run: LibrarySyncRun) async throws { }
    func replaceCollections(_ collections: [Collection], in run: LibrarySyncRun) async throws { }
    func upsertAlbumCollections(_ albumCollectionIDs: [String: [String]], in run: LibrarySyncRun) async throws { }
    func fetchPlaylists() async throws -> [LibraryPlaylistSnapshot] { [] }
    func fetchPlaylistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] { [] }
    func upsertPlaylists(_ playlists: [LibraryPlaylistSnapshot], in run: LibrarySyncRun) async throws { }
    func upsertPlaylistItems(
        _ items: [LibraryPlaylistItemSnapshot],
        playlistID: String,
        in run: LibrarySyncRun
    ) async throws { }
    func markAlbumsSeen(_ albumIDs: [String], in run: LibrarySyncRun) async throws { }
    func markTracksSeen(_ trackIDs: [String], in run: LibrarySyncRun) async throws { }
    func markTracksWithValidAlbumsSeen(in run: LibrarySyncRun) async throws { }
    func pruneRowsNotSeen(in run: LibrarySyncRun) async throws -> LibrarySyncPruneResult { .empty }
    func setSyncCheckpoint(_ checkpoint: LibrarySyncCheckpoint, in run: LibrarySyncRun?) async throws { }
    func syncCheckpoint(forKey key: String) async throws -> LibrarySyncCheckpoint? { nil }
    func completeIncrementalSync(_ run: LibrarySyncRun, refreshedAt: Date) async throws { }

    func artworkPath(for key: ArtworkKey) async throws -> String? {
        artworkPathByKey[key]
    }

    func setArtworkPath(_ path: String, for key: ArtworkKey) async throws {
        artworkPathByKey[key] = path
        setArtworkPathCalls.append(SetArtworkPathCall(path: path, key: key))
    }

    func deleteArtworkPath(for key: ArtworkKey) async throws {
        artworkPathByKey[key] = nil
        deletedArtworkKeys.append(key)
    }
}

@MainActor
private struct Fixture {
    let store: ArtworkStoreMock
    let session: ArtworkSessionMock
    let pipeline: ArtworkPipeline
    let cacheDirectory: URL

    init(maxCacheSizeBytes: Int = 250 * 1024 * 1024) throws {
        store = ArtworkStoreMock()
        session = ArtworkSessionMock()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtworkPipelineTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cacheDirectory = directory

        pipeline = ArtworkPipeline(
            store: store,
            session: session,
            cacheDirectoryURL: cacheDirectory,
            maxCacheSizeBytes: maxCacheSizeBytes
        )
    }
}
