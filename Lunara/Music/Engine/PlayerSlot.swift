import AVFoundation
import Foundation

final class PlayerSlot: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private(set) var trackID: String?
    private(set) var isActive = false
    var onPlaybackComplete: (() -> Void)?

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
