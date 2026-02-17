import Foundation
import Testing
@testable import Lunara

@MainActor
struct ArtworkPipelineProtocolTests {
    @Test
    func fetchThumbnail_withConfiguredResult_recordsRequestAndReturnsURL() async throws {
        let pipeline = ArtworkPipelineMock()
        let sourceURL = URL(string: "https://plex.example.com/thumb/album-1")!
        let cachedURL = URL(fileURLWithPath: "/tmp/artwork/thumb-album-1.jpg")
        pipeline.thumbnailResultByOwnerID["album-1"] = cachedURL

        let result = try await pipeline.fetchThumbnail(
            for: "album-1",
            ownerKind: .album,
            sourceURL: sourceURL
        )

        #expect(result == cachedURL)
        #expect(pipeline.thumbnailRequests == [
            .init(ownerID: "album-1", ownerKind: .album, sourceURL: sourceURL)
        ])
    }

    @Test
    func fetchFullSize_whenPipelineFails_propagatesOriginalLibraryError() async {
        let pipeline = ArtworkPipelineMock()
        pipeline.fetchFullSizeError = .timeout

        do {
            _ = try await pipeline.fetchFullSize(
                for: "album-2",
                ownerKind: .album,
                sourceURL: URL(string: "https://plex.example.com/full/album-2")!
            )
            Issue.record("Expected fetchFullSize to throw")
        } catch let error as LibraryError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }

        #expect(pipeline.fullSizeRequests.isEmpty)
    }

    @Test
    func invalidateCache_forKey_recordsExactImageKey() async throws {
        let pipeline = ArtworkPipelineMock()
        let key = ArtworkCacheKey(ownerID: "artist-7", ownerKind: .artist, imageKind: .thumbnail)

        try await pipeline.invalidateCache(for: key)

        #expect(pipeline.invalidatedKeys == [key])
    }

    @Test
    func invalidateCache_forOwner_recordsOwnerWideInvalidationRequest() async throws {
        let pipeline = ArtworkPipelineMock()

        try await pipeline.invalidateCache(for: "collection-4", ownerKind: .collection)

        #expect(pipeline.invalidatedOwners == [
            .init(ownerID: "collection-4", ownerKind: .collection)
        ])
    }

    @Test
    func invalidateAllCache_whenPipelineFails_propagatesOriginalLibraryError() async {
        let pipeline = ArtworkPipelineMock()
        pipeline.invalidateAllError = .databaseCorrupted

        do {
            try await pipeline.invalidateAllCache()
            Issue.record("Expected invalidateAllCache to throw")
        } catch let error as LibraryError {
            #expect(error == .databaseCorrupted)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }

        #expect(pipeline.invalidateAllCallCount == 0)
    }
}
