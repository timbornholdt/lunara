import Foundation
@testable import Lunara

@MainActor
final class ArtworkPipelineMock: ArtworkPipelineProtocol {
    struct FetchRequest: Equatable {
        let ownerID: String
        let ownerKind: ArtworkOwnerKind
        let sourceURL: URL?
    }

    struct InvalidateOwnerRequest: Equatable {
        let ownerID: String
        let ownerKind: ArtworkOwnerKind
    }

    var thumbnailResultByOwnerID: [String: URL?] = [:]
    var fullSizeResultByOwnerID: [String: URL?] = [:]

    var fetchThumbnailError: LibraryError?
    var fetchFullSizeError: LibraryError?
    var invalidateByKeyError: LibraryError?
    var invalidateByOwnerError: LibraryError?
    var invalidateAllError: LibraryError?

    private(set) var thumbnailRequests: [FetchRequest] = []
    private(set) var fullSizeRequests: [FetchRequest] = []
    private(set) var invalidatedKeys: [ArtworkCacheKey] = []
    private(set) var invalidatedOwners: [InvalidateOwnerRequest] = []
    private(set) var invalidateAllCallCount = 0

    /// When set, a `fetchFullSize` for this ownerID records its request and then
    /// suspends until `releaseFullSizeGate()` is called — used to model a slow /
    /// never-returning artwork fetch so tests can prove a track change isn't
    /// blocked behind it.
    var gateFullSizeForOwnerID: String?
    private var fullSizeGateContinuation: CheckedContinuation<Void, Never>?

    func releaseFullSizeGate() {
        let continuation = fullSizeGateContinuation
        fullSizeGateContinuation = nil
        gateFullSizeForOwnerID = nil
        continuation?.resume()
    }

    func fetchThumbnail(for ownerID: String, ownerKind: ArtworkOwnerKind, sourceURL: URL?) async throws -> URL? {
        if let fetchThumbnailError {
            throw fetchThumbnailError
        }

        thumbnailRequests.append(
            FetchRequest(ownerID: ownerID, ownerKind: ownerKind, sourceURL: sourceURL)
        )
        return thumbnailResultByOwnerID[ownerID] ?? nil
    }

    func fetchFullSize(for ownerID: String, ownerKind: ArtworkOwnerKind, sourceURL: URL?) async throws -> URL? {
        if let fetchFullSizeError {
            throw fetchFullSizeError
        }

        fullSizeRequests.append(
            FetchRequest(ownerID: ownerID, ownerKind: ownerKind, sourceURL: sourceURL)
        )

        if ownerID == gateFullSizeForOwnerID {
            await withCheckedContinuation { continuation in
                fullSizeGateContinuation = continuation
            }
        }

        return fullSizeResultByOwnerID[ownerID] ?? nil
    }

    func invalidateCache(for key: ArtworkCacheKey) async throws {
        if let invalidateByKeyError {
            throw invalidateByKeyError
        }

        invalidatedKeys.append(key)
    }

    func invalidateCache(for ownerID: String, ownerKind: ArtworkOwnerKind) async throws {
        if let invalidateByOwnerError {
            throw invalidateByOwnerError
        }

        invalidatedOwners.append(InvalidateOwnerRequest(ownerID: ownerID, ownerKind: ownerKind))
    }

    func invalidateAllCache() async throws {
        if let invalidateAllError {
            throw invalidateAllError
        }

        invalidateAllCallCount += 1
    }
}
