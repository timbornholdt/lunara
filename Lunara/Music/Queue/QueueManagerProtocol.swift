import Foundation
import Observation

struct QueueItem: Codable, Equatable, Hashable, Sendable {
    let trackID: String
    /// Stable Plex stream key (track.key). The playable URL is resolved lazily
    /// at play time from this key — never baked in at queue-build time — so a
    /// track downloaded/deleted after enqueue resolves to the right source and
    /// persisted queues never carry an expired X-Plex-Token.
    let streamKey: String
    let albumID: String
    let trackNumber: Int

    init(trackID: String, streamKey: String, albumID: String = "", trackNumber: Int = 0) {
        self.trackID = trackID
        self.streamKey = streamKey
        self.albumID = albumID
        self.trackNumber = trackNumber
    }
}

struct QueueSnapshot: Codable, Equatable, Sendable {
    let items: [QueueItem]
    let currentIndex: Int?
    let elapsed: TimeInterval
}

@MainActor
protocol QueueManagerProtocol: AnyObject, Observable {
    var items: [QueueItem] { get }
    var currentIndex: Int? { get }
    var currentItem: QueueItem? { get }
    var lastError: MusicError? { get }

    func playNow(_ items: [QueueItem])
    func playNext(_ items: [QueueItem])
    func playLater(_ items: [QueueItem])
    func play()
    func pause()
    func resume()
    func skipToNext()
    func skipBack()
    func skipTo(index: Int)
    func clear()
    func reconcile(removingTrackIDs: Set<String>)
    /// Offline availability for the given albums changed (a download completed or
    /// was removed). Re-resolves any pre-loaded next track whose album is affected
    /// so the engine never crossfades into a stale source.
    func offlineAvailabilityDidChange(forAlbums changedAlbumIDs: Set<String>)
}
