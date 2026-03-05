import AVFoundation
import Foundation

final class PlayerSlot {
    let playerNode: AVAudioPlayerNode
    private(set) var audioFile: AVAudioFile?
    private(set) var trackID: String?
    private(set) var isActive = false
    var onPlaybackComplete: (() -> Void)?

    /// Generation counter — incremented on every schedule. Completion handlers
    /// captured with an older generation are silently discarded so stale
    /// callbacks from a previous track/schedule cannot trigger handleTrackEnded.
    private var scheduleGeneration: Int = 0

    /// Manually tracked elapsed offset, updated before pause/stop so we can
    /// resume from the correct position after AVAudioEngine restarts.
    private var elapsedOffset: TimeInterval = 0

    var duration: TimeInterval {
        guard let file = audioFile else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    var elapsed: TimeInterval {
        guard let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return elapsedOffset
        }
        let nodeElapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        return elapsedOffset + max(0, nodeElapsed)
    }

    init() {
        self.playerNode = AVAudioPlayerNode()
    }

    func load(url: URL, trackID: String) throws {
        let file = try AVAudioFile(forReading: url)
        self.audioFile = file
        self.trackID = trackID
        self.elapsedOffset = 0
    }

    func scheduleAndPlay() {
        guard let audioFile else { return }
        playerNode.stop()
        elapsedOffset = 0
        scheduleGeneration += 1
        let expectedGeneration = scheduleGeneration
        let tid = trackID ?? "?"
        print("[Slot] scheduleAndPlay trackID=\(tid) gen=\(expectedGeneration)")
        playerNode.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let currentGen = self.scheduleGeneration
                let hasCallback = self.onPlaybackComplete != nil
                print("[Slot] .dataPlayedBack trackID=\(self.trackID ?? "nil") expectedGen=\(expectedGeneration) currentGen=\(currentGen) hasCallback=\(hasCallback)")
                guard expectedGeneration == currentGen else {
                    print("[Slot] STALE callback ignored (gen mismatch)")
                    return
                }
                self.onPlaybackComplete?()
            }
        }
        playerNode.play()
        isActive = true
    }

    func scheduleForGapless() {
        guard let audioFile else { return }
        playerNode.scheduleFile(audioFile, at: nil)
        isActive = true
    }

    func pause() {
        snapshotElapsed()
        playerNode.pause()
    }

    /// Re-schedules audio from the saved elapsed position after an engine restart.
    func resumeFromSavedPosition() {
        guard let audioFile else { return }
        let sampleRate = audioFile.processingFormat.sampleRate
        let targetFrame = AVAudioFramePosition(elapsedOffset * sampleRate)
        let totalFrames = audioFile.length
        let remainingFrames = AVAudioFrameCount(max(0, totalFrames - targetFrame))

        guard remainingFrames > 0 else { return }

        playerNode.stop()
        scheduleGeneration += 1
        let expectedGeneration = scheduleGeneration
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: targetFrame,
            frameCount: remainingFrames,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard expectedGeneration == self.scheduleGeneration else { return }
                self.onPlaybackComplete?()
            }
        }
        // Reset offset — elapsed will now be elapsedOffset + nodeElapsed,
        // but nodeElapsed starts fresh from 0 after re-schedule
        playerNode.play()
    }

    func resume() {
        playerNode.play()
    }

    func stop() {
        onPlaybackComplete = nil
        scheduleGeneration += 1
        playerNode.stop()
        isActive = false
        audioFile = nil
        trackID = nil
        elapsedOffset = 0
    }

    func seek(to time: TimeInterval) {
        guard let audioFile else { return }
        let sampleRate = audioFile.processingFormat.sampleRate
        let targetFrame = AVAudioFramePosition(time * sampleRate)
        let remainingFrames = AVAudioFrameCount(max(0, Int64(audioFile.length) - targetFrame))

        snapshotElapsed()
        elapsedOffset = time
        scheduleGeneration += 1
        playerNode.stop()
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: targetFrame,
            frameCount: remainingFrames,
            at: nil
        )
        playerNode.play()
    }

    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = newValue }
    }

    /// Captures current playback position into elapsedOffset so we can
    /// restore after engine restart.
    private func snapshotElapsed() {
        guard let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return
        }
        let nodeElapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        elapsedOffset += max(0, nodeElapsed)
    }
}
