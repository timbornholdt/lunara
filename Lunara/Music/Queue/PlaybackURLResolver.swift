import Foundation

/// Resolves the playable URL for a queue item at play time (offline-first).
///
/// The queue persists only stable identifiers (trackID + streamKey); the actual
/// URL is resolved here, on demand, so a track downloaded or deleted after it was
/// enqueued always plays from the correct source and persisted queues never carry
/// an expired Plex token.
protocol PlaybackURLResolving: Sendable {
    func resolvePlaybackURL(for item: QueueItem) async throws -> URL
}

final class PlaybackURLResolver: PlaybackURLResolving {
    private let offlineStore: OfflineStoreProtocol?
    private let library: LibraryRepoProtocol

    init(offlineStore: OfflineStoreProtocol?, library: LibraryRepoProtocol) {
        self.offlineStore = offlineStore
        self.library = library
    }

    func resolvePlaybackURL(for item: QueueItem) async throws -> URL {
        if let offlineStore, let localURL = try await offlineStore.localFileURL(forTrackID: item.trackID) {
            return localURL
        }
        return try await library.streamURL(forKey: item.streamKey)
    }
}
