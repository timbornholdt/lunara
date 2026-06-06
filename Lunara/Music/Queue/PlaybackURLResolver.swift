import Foundation

/// Resolves the playable URL for a queue item at play time (offline-first).
///
/// The queue persists only stable identifiers (trackID + streamKey); the actual
/// URL is resolved here, on demand, so a track downloaded or deleted after it was
/// enqueued always plays from the correct source and persisted queues never carry
/// an expired Plex token.
protocol PlaybackURLResolving: Sendable {
    /// Resolves the playable URL for a queue item.
    /// - Parameter allowOffline: when `false`, the offline store is bypassed and a
    ///   fresh stream URL is returned — used by reactive recovery so a retry never
    ///   re-picks a corrupt/missing offline file.
    func resolvePlaybackURL(for item: QueueItem, allowOffline: Bool) async throws -> URL
}

final class PlaybackURLResolver: PlaybackURLResolving {
    private let offlineStore: OfflineStoreProtocol?
    private let library: LibraryRepoProtocol

    init(offlineStore: OfflineStoreProtocol?, library: LibraryRepoProtocol) {
        self.offlineStore = offlineStore
        self.library = library
    }

    func resolvePlaybackURL(for item: QueueItem, allowOffline: Bool) async throws -> URL {
        if allowOffline,
           let offlineStore,
           let localURL = try await offlineStore.localFileURL(forTrackID: item.trackID) {
            return localURL
        }
        return try await library.streamURL(forKey: item.streamKey)
    }
}
