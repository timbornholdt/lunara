import Foundation
import Observation

struct QueueItem: Codable, Equatable, Hashable, Sendable {
    let trackID: String
    let url: URL
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
    func clear()
    func reconcile(removingTrackIDs: Set<String>)
}
