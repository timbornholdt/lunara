import Foundation
import Observation

@MainActor
protocol PlaybackEngineProtocol: AnyObject, Observable {
    var playbackState: PlaybackState { get }
    var elapsed: TimeInterval { get }
    var duration: TimeInterval { get }
    var currentTrackID: String? { get }

    func play(url: URL, trackID: String)
    func pause()
    func resume()
    func seek(to time: TimeInterval)
    func stop()
}

