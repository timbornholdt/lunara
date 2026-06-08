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
    private let slotA: any PlayerSlotProtocol
    private let slotB: any PlayerSlotProtocol
    private var activeSlot: any PlayerSlotProtocol
    private var inactiveSlot: any PlayerSlotProtocol

    /// UI-only timer for updating elapsed display. Runs on the default
    /// RunLoop mode — expected to stop when the app is backgrounded.
    private var elapsedTimer: Timer?

    /// One-shot GCD timer that fires at the exact crossfade start time.
    /// Uses DispatchSourceTimer so it keeps firing in background.
    private var crossfadeTriggerTimer: DispatchSourceTimer?

    /// GCD timer that ramps volume during an active crossfade.
    /// Runs only for the fade duration (2-12s), then stops.
    private var crossfadeRampTimer: DispatchSourceTimer?

    private(set) var isCrossfading = false
    private var crossfadeDuration: TimeInterval = 0

    private var pendingTransition: TransitionStyle?
    private var pendingTrackID: String?

    /// True only while playback is paused because of an audio-session interruption
    /// (phone call, Siri, another app). A deliberate user pause leaves this false,
    /// so `onInterruptionEnded` never auto-resumes a pause the user asked for
    /// (Lunara-gf5).
    private var pausedByInterruption = false

    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "CrossfadeEngine")
    private let telemetry: PlaybackTelemetryEmitting?

    var crossfadeEnabled: Bool = true

    init(
        audioSession: AudioSessionProtocol,
        telemetry: PlaybackTelemetryEmitting? = nil,
        slotFactory: () -> any PlayerSlotProtocol = { PlayerSlot() }
    ) {
        self.audioSession = audioSession
        self.telemetry = telemetry
        let a = slotFactory()
        let b = slotFactory()
        self.slotA = a
        self.slotB = b
        self.activeSlot = a
        self.inactiveSlot = b

        wireInterruptions()
    }

    /// Emits a telemetry event stamped with the AUTHORITATIVE loaded-slot count
    /// (a slot's `trackID` is non-nil iff it holds a file). Guarded so nothing is
    /// built when recording is off.
    private func emit(_ kind: PlaybackTelemetryEvent.Kind) {
        guard telemetry?.isEnabled == true else { return }
        let loadedSlots = [slotA, slotB].filter { $0.trackID != nil }.count
        telemetry?.record(
            PlaybackTelemetryEvent(
                kind: kind,
                slots: loadedSlots,
                state: stateName,
                trackID: currentTrackID,
                durationSeconds: duration > 0 ? duration : nil,
                crossfadeEnabled: crossfadeEnabled
            )
        )
    }

    private var stateName: String {
        switch playbackState {
        case .idle: return "idle"
        case .buffering: return "buffering"
        case .playing: return "playing"
        case .paused: return "paused"
        case .error: return "error"
        }
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
        pausedByInterruption = false

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
        scheduleCrossfadeTriggerIfNeeded()
        emit(.play)
    }

    func pause() {
        // User-initiated pause (transport control / lock screen). Clear the
        // interruption-origin flag so a later interruption-ended cannot auto-resume
        // a deliberate pause (Lunara-gf5).
        pausedByInterruption = false
        performPause()
    }

    /// Pauses playback without altering `pausedByInterruption`. Callers set that
    /// flag to record whether the pause was user- or interruption-initiated.
    private func performPause() {
        activeSlot.pause()
        if isCrossfading {
            inactiveSlot.pause()
            cancelCrossfadeRampTimer()
        }
        cancelCrossfadeTriggerTimer()
        stopElapsedTimer()
        if playbackState != .idle && !playbackState.hasError {
            playbackState = .paused
        }
        emit(.pause)
    }

    func resume() {
        guard currentTrackID != nil else {
            transitionToError(MusicError.invalidState(reason: "No track is loaded.").userMessage)
            return
        }

        pausedByInterruption = false
        activeSlot.resume()
        if isCrossfading {
            inactiveSlot.resume()
        }

        if isCrossfading {
            startCrossfadeRampTimer()
        } else {
            scheduleCrossfadeTriggerIfNeeded()
        }
        playbackState = .playing
        startElapsedTimer()
        emit(.resume)
    }

    func seek(to time: TimeInterval) {
        cancelActiveCrossfade()
        activeSlot.seek(to: time)
        elapsed = max(0, time)
        scheduleCrossfadeTriggerIfNeeded()
        emit(.seek)
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
        emit(.stop)
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
                    self.emit(.skip)
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
            logger.debug("[CF] prepareNext: trackID=\(trackID, privacy: .public) transition=\(String(describing: transition), privacy: .public)")
            scheduleCrossfadeTriggerIfNeeded()
            emit(.prepareNext)
        } catch {
            logger.error("Failed to prepare next track: \(error.localizedDescription, privacy: .public)")
            pendingTransition = nil
            pendingTrackID = nil
        }
    }

    func clearPreparedNext() {
        // While a fade is active the "next" track is already audibly playing in a
        // promoting slot; tearing it down would glitch. Only discard a buffer that
        // hasn't started crossfading yet.
        guard !isCrossfading else { return }
        cancelCrossfadeTriggerTimer()
        inactiveSlot.stop()
        pendingTransition = nil
        pendingTrackID = nil
        logger.debug("[CF] clearPreparedNext: discarded staged next track")
    }

    // MARK: - Elapsed Timer (UI only)

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
    }

    // MARK: - Crossfade Trigger (one-shot, background-safe)

    /// Schedules a one-shot GCD timer to fire at the crossfade start time.
    /// Uses DispatchSourceTimer so it keeps firing even when the app is
    /// backgrounded with audio playing. Generous leeway allows the system
    /// to coalesce wakeups for power efficiency.
    private func scheduleCrossfadeTriggerIfNeeded() {
        cancelCrossfadeTriggerTimer()

        guard !isCrossfading else { return }
        guard let transition = pendingTransition,
              case .crossfade(let startTime, _) = transition else { return }

        let currentElapsed = activeSlot.elapsed
        let delay = startTime - currentElapsed

        if delay <= 0 {
            logger.debug("[CF] crossfade trigger: start time already passed, beginning immediately")
            beginCrossfade()
            return
        }

        logger.debug("[CF] crossfade trigger: scheduled in \(delay, privacy: .public)s (startTime=\(startTime, privacy: .public) elapsed=\(currentElapsed, privacy: .public))")

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.beginCrossfade()
            }
        }
        timer.resume()
        crossfadeTriggerTimer = timer
    }

    private func cancelCrossfadeTriggerTimer() {
        crossfadeTriggerTimer?.cancel()
        crossfadeTriggerTimer = nil
    }

    // MARK: - Crossfade Ramp (active fade, background-safe)

    private func startCrossfadeRampTimer() {
        cancelCrossfadeRampTimer()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.updateCrossfade()
            }
        }
        timer.resume()
        crossfadeRampTimer = timer
    }

    private func cancelCrossfadeRampTimer() {
        crossfadeRampTimer?.cancel()
        crossfadeRampTimer = nil
    }

    // MARK: - Transition Logic

    func beginCrossfade() {
        guard let transition = pendingTransition,
              case .crossfade(_, let fadeDuration) = transition else { return }

        cancelCrossfadeTriggerTimer()

        logger.debug("[CF] beginCrossfade: active=\(self.activeSlot.trackID ?? "nil", privacy: .public) inactive=\(self.inactiveSlot.trackID ?? "nil", privacy: .public) fadeDuration=\(fadeDuration)")
        isCrossfading = true
        crossfadeDuration = fadeDuration

        inactiveSlot.onPlaybackComplete = nil
        inactiveSlot.volume = 0
        inactiveSlot.play()

        startCrossfadeRampTimer()
        emit(.crossfadeBegin)
    }

    func updateCrossfade() {
        guard isCrossfading else { return }

        // Drive progress from the INCOMING slot's clock. It starts at 0 when the
        // fade begins, advances monotonically, and freezes on pause — unlike the
        // outgoing slot's clock, which resets to 0 at end-of-file and would wedge
        // the crossfade (progress never reaching 1.0) if the track ended mid-fade.
        let progress = min(1.0, inactiveSlot.elapsed / crossfadeDuration)
        let angle = progress * .pi / 2.0
        activeSlot.volume = Float(cos(angle))
        inactiveSlot.volume = Float(sin(angle))

        if progress >= 1.0 {
            completeCrossfade()
        }
    }

    func completeCrossfade() {
        // Idempotent: the ramp timer and the outgoing slot's EOF callback can
        // both reach here within the same ~100ms window. Without this guard a
        // second call would stop and swap out the freshly-promoted active track.
        guard isCrossfading else { return }
        cancelCrossfadeRampTimer()

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
        emit(.crossfadeComplete)
    }

    func handleTrackEnded() {
        logger.debug("[CF] handleTrackEnded: state=\(String(describing: self.playbackState), privacy: .public) isCrossfading=\(self.isCrossfading) activeTrack=\(self.activeSlot.trackID ?? "nil", privacy: .public) inactiveTrack=\(self.inactiveSlot.trackID ?? "nil", privacy: .public) pendingTransition=\(String(describing: self.pendingTransition), privacy: .public)")
        // If the outgoing track reaches its end while a crossfade is still
        // ramping, finish the crossfade now rather than dropping the callback.
        // Otherwise the fade could wedge (both slots pinned, incoming muted).
        if isCrossfading {
            logger.debug("[CF] handleTrackEnded: outgoing ended mid-crossfade, force-completing")
            completeCrossfade()
            return
        }

        // Guard against spurious callbacks (e.g. node stopped during seek or interruption)
        guard playbackState == .playing else {
            logger.debug("[CF] handleTrackEnded: SKIPPED (not playing)")
            return
        }

        cancelCrossfadeTriggerTimer()

        if pendingTransition != nil, inactiveSlot.trackID != nil {
            // A next track is loaded — swap and play immediately.
            // This handles both .gapless transitions and .crossfade transitions
            // where the fade didn't start (e.g. app was backgrounded and the
            // trigger timer couldn't fire, or the track was shorter than expected).
            logger.debug("[CF] handleTrackEnded: swapping to next track (immediate)")
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
            emit(.play)
        } else {
            // No next track prepared - signal idle
            logger.debug("[CF] handleTrackEnded: no next track, going idle")
            stopElapsedTimer()
            activeSlot.stop()
            currentTrackID = nil
            playbackState = .idle
            elapsed = 0
            duration = 0
            emit(.stop)
        }
    }

    /// Cancels an in-progress crossfade ramp but keeps the pending transition
    /// so it can still trigger if the user hasn't seeked past it.
    private func cancelActiveCrossfade() {
        cancelCrossfadeRampTimer()
        cancelCrossfadeTriggerTimer()
        if isCrossfading {
            // Keep the preloaded next track loaded (just rewound and muted) rather
            // than discarding it, so the pending transition can re-trigger when the
            // current track reaches the crossfade point again (e.g. after the user
            // scrubs backward mid-fade). Stopping it here would leave the engine
            // crossfading into an empty slot — silence, with the next song never
            // playing.
            inactiveSlot.pause()
            inactiveSlot.seek(to: 0)
            inactiveSlot.volume = 0
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
        emit(.error)
    }

    // MARK: - Audio Interruptions

    private func wireInterruptions() {
        audioSession.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            // Record that THIS pause is interruption-initiated before pausing, so
            // it (and only it) is eligible for auto-resume when the interruption ends.
            self.pausedByInterruption = true
            self.performPause()
        }
        audioSession.onInterruptionEnded = { [weak self] shouldResume in
            guard let self else { return }
            let wasInterrupted = self.pausedByInterruption
            self.pausedByInterruption = false
            // Auto-resume only an interruption-initiated pause the system says is
            // resumable — never a deliberate user pause (Lunara-gf5).
            guard wasInterrupted, shouldResume, self.playbackState == .paused else { return }
            // Re-activate the audio session — the system may have deactivated it.
            try? self.audioSession.configureForPlayback()
            self.resume()
        }
    }
}
