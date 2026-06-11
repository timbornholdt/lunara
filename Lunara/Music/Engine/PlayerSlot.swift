import AVFoundation
import Foundation

/// The surface `CrossfadeEngine` uses to drive a player slot. Extracted so the
/// engine can be unit-tested with a mock slot (no real `AVAudioPlayer`/file).
protocol PlayerSlotProtocol: AnyObject {
    var trackID: String? { get }
    var isActive: Bool { get }
    var duration: TimeInterval { get }
    var elapsed: TimeInterval { get }
    var volume: Float { get set }
    /// Whether the loaded source is still healthy enough to start playing.
    /// AVAudioPlayer plays an unlinked-but-open file as silence rather than
    /// erroring, so this re-checks the source (file existence) at fade time
    /// (Lunara-uww.3.8).
    var isReadyForPlayback: Bool { get }
    var onPlaybackComplete: (() -> Void)? { get set }
    func load(url: URL, trackID: String) throws
    func play()
    func pause()
    func resume()
    func stop()
    func seek(to time: TimeInterval)
}

final class PlayerSlot: NSObject, AVAudioPlayerDelegate, PlayerSlotProtocol {
    private var player: AVAudioPlayer?
    private var loadedURL: URL?
    private(set) var trackID: String?
    private(set) var isActive = false
    var onPlaybackComplete: (() -> Void)?

    var isReadyForPlayback: Bool {
        guard player != nil, let loadedURL else { return false }
        guard loadedURL.isFileURL else { return true }
        return FileManager.default.fileExists(atPath: loadedURL.path)
    }

    var duration: TimeInterval {
        player?.duration ?? 0
    }

    var elapsed: TimeInterval {
        player?.currentTime ?? 0
    }

    func load(url: URL, trackID: String) throws {
        let newPlayer = try AVAudioPlayer(contentsOf: url)
        newPlayer.delegate = self
        newPlayer.prepareToPlay()
        self.player = newPlayer
        self.loadedURL = url
        self.trackID = trackID
    }

    func play() {
        player?.play()
        isActive = true
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        player?.play()
    }

    func stop() {
        onPlaybackComplete = nil
        player?.stop()
        player = nil
        loadedURL = nil
        isActive = false
        trackID = nil
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
    }

    var volume: Float {
        get { player?.volume ?? 0 }
        set { player?.volume = newValue }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackComplete?()
        }
    }
}
