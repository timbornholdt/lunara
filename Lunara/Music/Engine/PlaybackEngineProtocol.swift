import Foundation
import Observation

@MainActor
protocol PlaybackEngineProtocol: AnyObject, Observable {
    var playbackState: PlaybackState { get }
    var elapsed: TimeInterval { get }
    var duration: TimeInterval { get }
    var currentTrackID: String? { get }
    var crossfadeEnabled: Bool { get set }
    /// Loudness leveling on/off (Lunara-bvs); applies from the next track load.
    var levelingEnabled: Bool { get set }

    func play(url: URL, trackID: String)
    /// Play with a loudness-leveling offset in dB (negative attenuates; the
    /// engine clamps boosts — player volume cannot exceed 1.0). nil = unleveled.
    func play(url: URL, trackID: String, gainDB: Float?)
    func pause()
    func resume()
    func seek(to time: TimeInterval)
    func stop()
    func prepareNext(url: URL, trackID: String, transition: TransitionStyle)
    func prepareNext(url: URL, trackID: String, transition: TransitionStyle, gainDB: Float?)
    /// Discards any track previously handed to `prepareNext` that has not yet
    /// started crossfading, so a stale preloaded buffer (e.g. a now-deleted
    /// offline file) is never faded into. No-op while a crossfade is active.
    func clearPreparedNext()
    func signalBuffering()
    func skipWithFade()
    /// Scene foreground/background transitions, so the engine can pause
    /// UI-only work (the elapsed timer) while invisible (Lunara-n09).
    func sceneDidChangeActivity(isActive: Bool)
}

extension PlaybackEngineProtocol {
    // Gain-unaware conformers (test doubles, simple engines) drop the offset.
    var levelingEnabled: Bool {
        get { true }
        set { }
    }
    func play(url: URL, trackID: String, gainDB: Float?) {
        play(url: url, trackID: trackID)
    }
    func prepareNext(url: URL, trackID: String, transition: TransitionStyle, gainDB: Float?) {
        prepareNext(url: url, trackID: trackID, transition: transition)
    }
    func prepareNext(url: URL, trackID: String, transition: TransitionStyle) {}
    func clearPreparedNext() {}
    func signalBuffering() {}
    func skipWithFade() { stop() }
    func sceneDidChangeActivity(isActive: Bool) {}
}

