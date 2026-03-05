import Foundation
import Observation
import os

@MainActor
@Observable
final class CrossfadeEngine: PlaybackEngineProtocol {
    private(set) var playbackState: PlaybackState = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentTrackID: String?

    private let audioSession: AudioSessionProtocol
    private let slotA = PlayerSlot()
    private let slotB = PlayerSlot()
    private var activeSlot: PlayerSlot
    private var inactiveSlot: PlayerSlot

    private var crossfadeTimer: Timer?
    private var elapsedTimer: Timer?
    private var isCrossfading = false
    private var crossfadeStartTime: TimeInterval = 0
    private var crossfadeDuration: TimeInterval = 0

    private var pendingTransition: TransitionStyle?
    private var pendingTrackID: String?

    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "CrossfadeEngine")

    var crossfadeEnabled: Bool = true

    init(audioSession: AudioSessionProtocol) {
        self.audioSession = audioSession
        self.activeSlot = slotA
        self.inactiveSlot = slotB

        wireInterruptions()
    }

    func play(url: URL, trackID: String) {
        do {
            try audioSession.configureForPlayback()
        } catch {
            transitionToError(MusicError.audioSessionFailed.userMessage)
            return
        }

        cancelCrossfade()
        stopElapsedTimer()

        do {
            try activeSlot.load(url: url, trackID: trackID)
        } catch {
            logger.error("Failed to load audio file: \(error.localizedDescription, privacy: .public)")
            transitionToError(MusicError.streamFailed(reason: "Failed to load audio file.").userMessage)
            return
        }

        activeSlot.volume = 1.0
        logger.debug("[CF] play: setting onPlaybackComplete for trackID=\(trackID, privacy: .public)")
        activeSlot.onPlaybackComplete = { [weak self] in
            self?.handleTrackEnded()
        }
        activeSlot.play()

        currentTrackID = trackID
        elapsed = 0
        duration = activeSlot.duration
        playbackState = .playing

        startElapsedTimer()
        scheduleTransitionIfNeeded()
    }

    func pause() {
        activeSlot.pause()
        if isCrossfading {
            inactiveSlot.pause()
            crossfadeTimer?.invalidate()
        }
        stopElapsedTimer()
        if playbackState != .idle && !playbackState.hasError {
            playbackState = .paused
        }
    }

    func resume() {
        guard currentTrackID != nil else {
            transitionToError(MusicError.invalidState(reason: "No track is loaded.").userMessage)
            return
        }

        activeSlot.resume()
        if isCrossfading {
            inactiveSlot.resume()
        }

        if isCrossfading {
            startCrossfadeTimer()
        }
        playbackState = .playing
        startElapsedTimer()
    }

    func seek(to time: TimeInterval) {
        cancelActiveCrossfade()
        activeSlot.seek(to: time)
        elapsed = max(0, time)
    }

    func stop() {
        cancelCrossfade()
        stopElapsedTimer()
        activeSlot.stop()
        inactiveSlot.stop()
        playbackState = .idle
        currentTrackID = nil
        elapsed = 0
        duration = 0
    }

    func signalBuffering() {
        if playbackState != .buffering {
            playbackState = .buffering
        }
    }

    func skipWithFade() {
        guard playbackState == .playing else {
            stop()
            return
        }

        // Fast 500ms equal-power fade-out
        cancelCrossfade()
        let fadeDuration = 0.5
        let fadeSteps = 10
        let stepInterval = fadeDuration / Double(fadeSteps)
        var step = 0

        Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                step += 1
                let progress = Double(step) / Double(fadeSteps)
                let angle = progress * .pi / 2.0
                self.activeSlot.volume = Float(cos(angle))

                if step >= fadeSteps {
                    timer.invalidate()
                    self.stopElapsedTimer()
                    self.activeSlot.stop()
                    self.inactiveSlot.stop()
                    self.currentTrackID = nil
                    self.playbackState = .idle
                    self.elapsed = 0
                    self.duration = 0
                }
            }
        }
    }

    func prepareNext(url: URL, trackID: String, transition: TransitionStyle) {
        guard crossfadeEnabled else {
            pendingTransition = nil
            pendingTrackID = nil
            return
        }

        do {
            try inactiveSlot.load(url: url, trackID: trackID)
            pendingTransition = transition
            pendingTrackID = trackID
            scheduleTransitionIfNeeded()
        } catch {
            logger.error("Failed to prepare next track: \(error.localizedDescription, privacy: .public)")
            pendingTransition = nil
            pendingTrackID = nil
        }
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateElapsed()
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateElapsed() {
        guard activeSlot.isActive else { return }
        let newElapsed = activeSlot.elapsed
        if newElapsed != elapsed {
            elapsed = newElapsed
        }

        // Check if we should start crossfade
        if let transition = pendingTransition, case .crossfade(let startTime, _) = transition {
            if newElapsed >= startTime && !isCrossfading {
                beginCrossfade()
            }
        }
    }

    // MARK: - Transition Logic

    private func scheduleTransitionIfNeeded() {
        // Nothing to schedule - transition check happens in updateElapsed
    }

    private func beginCrossfade() {
        guard let transition = pendingTransition,
              case .crossfade(_, let fadeDuration) = transition else { return }

        logger.debug("[CF] beginCrossfade: active=\(self.activeSlot.trackID ?? "nil", privacy: .public) inactive=\(self.inactiveSlot.trackID ?? "nil", privacy: .public) fadeDuration=\(fadeDuration)")
        isCrossfading = true
        crossfadeDuration = fadeDuration
        crossfadeStartTime = elapsed

        inactiveSlot.onPlaybackComplete = nil
        inactiveSlot.volume = 0
        inactiveSlot.play()

        startCrossfadeTimer()
    }

    private func startCrossfadeTimer() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateCrossfade()
            }
        }
    }

    private func updateCrossfade() {
        guard isCrossfading else { return }

        let progress = min(1.0, (elapsed - crossfadeStartTime) / crossfadeDuration)
        let angle = progress * .pi / 2.0
        activeSlot.volume = Float(cos(angle))
        inactiveSlot.volume = Float(sin(angle))

        if progress >= 1.0 {
            completeCrossfade()
        }
    }

    private func completeCrossfade() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil

        logger.debug("[CF] completeCrossfade: stopping old active=\(self.activeSlot.trackID ?? "nil", privacy: .public), new active will be=\(self.inactiveSlot.trackID ?? "nil", privacy: .public)")
        activeSlot.stop()

        // Swap slots
        let temp = activeSlot
        activeSlot = inactiveSlot
        inactiveSlot = temp

        activeSlot.volume = 1.0
        activeSlot.onPlaybackComplete = { [weak self] in
            self?.handleTrackEnded()
        }
        isCrossfading = false

        currentTrackID = activeSlot.trackID
        elapsed = 0
        duration = activeSlot.duration
        pendingTransition = nil
        pendingTrackID = nil
        logger.debug("[CF] completeCrossfade: done. activeTrackID=\(self.activeSlot.trackID ?? "nil", privacy: .public)")
    }

    private func handleTrackEnded() {
        logger.debug("[CF] handleTrackEnded: state=\(String(describing: self.playbackState), privacy: .public) isCrossfading=\(self.isCrossfading) activeTrack=\(self.activeSlot.trackID ?? "nil", privacy: .public) inactiveTrack=\(self.inactiveSlot.trackID ?? "nil", privacy: .public)")
        // Guard against spurious callbacks (e.g. node stopped during seek or interruption)
        guard playbackState == .playing, !isCrossfading else {
            logger.debug("[CF] handleTrackEnded: SKIPPED (not playing)")
            return
        }

        if let transition = pendingTransition, case .gapless = transition {
            // For gapless, the inactive slot should already be loaded
            activeSlot.stop()
            let temp = activeSlot
            activeSlot = inactiveSlot
            inactiveSlot = temp

            activeSlot.volume = 1.0
            activeSlot.onPlaybackComplete = { [weak self] in
                self?.handleTrackEnded()
            }
            activeSlot.play()

            currentTrackID = activeSlot.trackID
            elapsed = 0
            duration = activeSlot.duration
            pendingTransition = nil
            pendingTrackID = nil
        } else {
            // No next track prepared - signal idle
            stopElapsedTimer()
            activeSlot.stop()
            currentTrackID = nil
            playbackState = .idle
            elapsed = 0
            duration = 0
        }
    }

    /// Cancels an in-progress crossfade ramp but keeps the pending transition
    /// so it can still trigger if the user hasn't seeked past it.
    private func cancelActiveCrossfade() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        if isCrossfading {
            inactiveSlot.stop()
            activeSlot.volume = 1.0
            isCrossfading = false
        }
    }

    /// Cancels everything — active ramp and pending preparation.
    private func cancelCrossfade() {
        cancelActiveCrossfade()
        pendingTransition = nil
        pendingTrackID = nil
    }

    private func transitionToError(_ message: String) {
        cancelCrossfade()
        stopElapsedTimer()
        playbackState = .error(message)
        activeSlot.stop()
        inactiveSlot.stop()
    }

    // MARK: - Audio Interruptions

    private func wireInterruptions() {
        audioSession.onInterruptionBegan = { [weak self] in
            self?.pause()
        }
        audioSession.onInterruptionEnded = { [weak self] _ in
            guard let self, self.playbackState == .paused else { return }
            // Re-activate the audio session — the system may have deactivated it.
            try? self.audioSession.configureForPlayback()
            self.resume()
        }
    }
}
