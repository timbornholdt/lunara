import Foundation
import Observation

struct QueueItem: Codable, Equatable, Hashable, Sendable {
    let trackID: String
    let url: URL
    let albumID: String
    let trackNumber: Int

    init(trackID: String, url: URL, albumID: String = "", trackNumber: Int = 0) {
        self.trackID = trackID
        self.url = url
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
}
