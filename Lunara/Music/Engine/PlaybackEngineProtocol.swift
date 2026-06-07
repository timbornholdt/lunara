import Foundation
import Observation

@MainActor
protocol PlaybackEngineProtocol: AnyObject, Observable {
    var playbackState: PlaybackState { get }
    var elapsed: TimeInterval { get }
    var duration: TimeInterval { get }
    var currentTrackID: String? { get }
    var crossfadeEnabled: Bool { get set }

    func play(url: URL, trackID: String)
    func pause()
    func resume()
    func seek(to time: TimeInterval)
    func stop()
    func prepareNext(url: URL, trackID: String, transition: TransitionStyle)
    /// Discards any track previously handed to `prepareNext` that has not yet
    /// started crossfading, so a stale preloaded buffer (e.g. a now-deleted
    /// offline file) is never faded into. No-op while a crossfade is active.
    func clearPreparedNext()
    func signalBuffering()
    func skipWithFade()
}

extension PlaybackEngineProtocol {
    func prepareNext(url: URL, trackID: String, transition: TransitionStyle) {}
    func clearPreparedNext() {}
    func signalBuffering() {}
    func skipWithFade() { stop() }
}

