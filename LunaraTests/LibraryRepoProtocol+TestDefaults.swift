import Foundation
@testable import Lunara

/// Test-only default for keyset pagination. Production conformers (LibraryRepo
/// store-backed, PlexAPIClient stub) implement `queryAlbums(filter:after:limit:)`
/// directly; the many view-model test doubles that don't exercise paging satisfy
/// conformance by slicing their existing `queryAlbums(filter:)` result in memory.
extension LibraryRepoProtocol {
    func queryAlbums(filter: AlbumQueryFilter, after: AlbumCursor?, limit: Int) async throws -> [Album] {
        let all = try await queryAlbums(filter: filter)
        let start: Int
        if let after {
            start = all.firstIndex {
                ($0.artistName, $0.title, $0.plexID) > (after.artistName, after.title, after.plexID)
            } ?? all.count
        } else {
            start = 0
        }
        return Array(all[start...].prefix(limit))
    }
}

/// Mirror of the keyset-pagination default at the store layer, so `LibraryStoreProtocol`
/// test doubles that don't exercise paging satisfy conformance.
extension LibraryStoreProtocol {
    func queryAlbums(filter: AlbumQueryFilter, after: AlbumCursor?, limit: Int) async throws -> [Album] {
        let all = try await queryAlbums(filter: filter)
        let start: Int
        if let after {
            start = all.firstIndex {
                ($0.artistName, $0.title, $0.plexID) > (after.artistName, after.title, after.plexID)
            } ?? all.count
        } else {
            start = 0
        }
        return Array(all[start...].prefix(limit))
    }
}

/// Test-only default for the lazy stream-key resolution requirement.
///
/// Production conformers (LibraryRepo, PlexAPIClient) implement `streamURL(forKey:)`
/// directly. The many view-model test doubles don't exercise key-based resolution —
/// playback-URL resolution is tested via `PlaybackURLResolving` mocks — so this
/// default lets them satisfy conformance by delegating to their existing
/// `streamURL(for:)` with a synthetic key-carrying track.
extension LibraryRepoProtocol {
    func streamURL(forKey key: String) async throws -> URL {
        try await streamURL(
            for: Track(
                plexID: "",
                albumID: "",
                title: "",
                trackNumber: 0,
                duration: 0,
                artistName: "",
                key: key,
                thumbURL: nil
            )
        )
    }
}
