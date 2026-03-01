import Foundation

public enum ArtworkOwnerKind: String, Equatable, Sendable {
    case album
    case artist
    case collection
    case playlist
}

public enum ArtworkImageKind: String, Equatable, Sendable {
    case thumbnail
    case fullSize
}

public struct ArtworkCacheKey: Equatable, Hashable, Sendable {
    public let ownerID: String
    public let ownerKind: ArtworkOwnerKind
    public let imageKind: ArtworkImageKind

    public init(ownerID: String, ownerKind: ArtworkOwnerKind, imageKind: ArtworkImageKind) {
        self.ownerID = ownerID
        self.ownerKind = ownerKind
        self.imageKind = imageKind
    }
}

@MainActor
public protocol ArtworkPipelineProtocol: AnyObject {
    /// Fetches or resolves cached thumbnail artwork (~300px) for an owner.
    /// Returns a local file URL when artwork is available.
    func fetchThumbnail(for ownerID: String, ownerKind: ArtworkOwnerKind, sourceURL: URL?) async throws -> URL?

    /// Fetches or resolves cached full-size artwork (~1024px) for an owner.
    /// Returns a local file URL when artwork is available.
    func fetchFullSize(for ownerID: String, ownerKind: ArtworkOwnerKind, sourceURL: URL?) async throws -> URL?

    /// Invalidates one cached artwork entry.
    func invalidateCache(for key: ArtworkCacheKey) async throws

    /// Invalidates all cached variants for a specific owner.
    func invalidateCache(for ownerID: String, ownerKind: ArtworkOwnerKind) async throws

    /// Invalidates all artwork cache entries managed by the pipeline.
    func invalidateAllCache() async throws
}
