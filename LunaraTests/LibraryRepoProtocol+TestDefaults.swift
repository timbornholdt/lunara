import Foundation
@testable import Lunara

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
