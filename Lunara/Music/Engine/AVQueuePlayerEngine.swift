import AVFoundation
import Foundation
import Observation
import OSLog

protocol PlaybackTimeoutScheduling: AnyObject {
    @discardableResult
    func schedule(after delay: TimeInterval, action: @escaping @Sendable () -> Void) -> PlaybackTimeoutTask
}

protocol PlaybackTimeoutTask: AnyObject {
    func cancel()
}

protocol PlaybackDiagnosticsLogging: AnyObject {
    func logPlaybackFailure(reason: String, sanitizedURLContext: String)
}

final class OSPlaybackDiagnosticsLogger: PlaybackDiagnosticsLogging {
    private let logger: Logger

    init(logger: Logger = Logger(subsystem: "Lunara", category: "PlaybackDiagnostics")) {
        self.logger = logger
    }

    func logPlaybackFailure(reason: String, sanitizedURLContext: String) {
        logger.error("Playback failure reason=\(reason, privacy: .public) url=\(sanitizedURLContext, privacy: .public)")
    }
}

final class DispatchQueuePlaybackTimeoutScheduler: PlaybackTimeoutScheduling {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    func schedule(after delay: TimeInterval, action: @escaping @Sendable () -> Void) -> PlaybackTimeoutTask {
        let workItem = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
        return DispatchQueuePlaybackTimeoutTask(workItem: workItem)
    }
}

private final class DispatchQueuePlaybackTimeoutTask: PlaybackTimeoutTask {
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        workItem.cancel()
    }
}

@MainActor
@Observable
final class AVQueuePlayerEngine: PlaybackEngineProtocol {
    private(set) var playbackState: PlaybackState = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentTrackID: String?

    private let audioSession: AudioSessionProtocol
    private let driver: PlaybackEngineDriver
    private let timeoutScheduler: PlaybackTimeoutScheduling
    private let diagnosticsLogger: PlaybackDiagnosticsLogging
    private let bufferingTimeout: TimeInterval

    private var bufferingTimeoutTask: PlaybackTimeoutTask?
    private var activePlaybackURL: URL?
    private var hasLoggedFailureForActivePlayback = false

    init(
        audioSession: AudioSessionProtocol,
        driver: PlaybackEngineDriver? = nil,
        timeoutScheduler: PlaybackTimeoutScheduling? = nil,
        diagnosticsLogger: PlaybackDiagnosticsLogging? = nil,
        bufferingTimeout: TimeInterval = 8
    ) {
        self.audioSession = audioSession
        self.driver = driver ?? AVQueuePlayerDriver()
        self.timeoutScheduler = timeoutScheduler ?? DispatchQueuePlaybackTimeoutScheduler()
        self.diagnosticsLogger = diagnosticsLogger ?? OSPlaybackDiagnosticsLogger()
        self.bufferingTimeout = bufferingTimeout

        wireDependencies()
    }

    func play(url: URL, trackID: String) {
        do {
            try audioSession.configureForPlayback()
        } catch {
            transitionToError(MusicError.audioSessionFailed.userMessage)
            return
        }

        currentTrackID = trackID
        activePlaybackURL = url
        hasLoggedFailureForActivePlayback = false
        elapsed = 0
        duration = 0

        transitionToBuffering()
        driver.play(url: url, trackID: trackID)
    }

    func prepareNext(url: URL, trackID: String) {
        driver.prepareNext(url: url, trackID: trackID)
    }

    func pause() {
        cancelBufferingTimeout()
        driver.pause()
        if playbackState != .idle && !playbackState.hasError {
            playbackState = .paused
        }
    }

    func resume() {
        guard currentTrackID != nil else {
            transitionToError(MusicError.invalidState(reason: "No track is loaded.").userMessage)
            return
        }

        transitionToBuffering()
        driver.resume()
    }

    func seek(to time: TimeInterval) {
        driver.seek(to: time)
        elapsed = max(0, time)
    }

    func stop() {
        cancelBufferingTimeout()
        driver.stop()
        playbackState = .idle
        currentTrackID = nil
        elapsed = 0
        duration = 0
    }

    private func wireDependencies() {
        driver.onTimeControlStatusChanged = { [weak self] status in
            self?.handleTimeControlStatus(status)
        }

        driver.onCurrentTrackIDChanged = { [weak self] trackID in
            self?.currentTrackID = trackID
        }

        driver.onCurrentItemFailed = { [weak self] message in
            self?.logPlaybackFailureIfNeeded(reason: message)
            self?.transitionToError(message)
        }

        driver.onCurrentItemEnded = { [weak self] in
            guard let self else { return }
            if self.currentTrackID == nil {
                self.playbackState = .idle
                self.elapsed = 0
                self.duration = 0
            }
        }

        driver.onElapsedChanged = { [weak self] elapsed in
            self?.elapsed = elapsed
        }

        driver.onDurationChanged = { [weak self] duration in
            self?.duration = duration
        }

        audioSession.onInterruptionBegan = { [weak self] in
            self?.pause()
        }

        audioSession.onInterruptionEnded = { [weak self] shouldResume in
            guard shouldResume else { return }
            self?.resume()
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .waitingToPlayAtSpecifiedRate:
            if playbackState != .idle && !playbackState.hasError {
                transitionToBuffering()
            }
        case .playing:
            cancelBufferingTimeout()
            playbackState = .playing
        case .paused:
            if playbackState == .idle || playbackState.hasError || playbackState == .buffering {
                return
            }
            playbackState = .paused
        @unknown default:
            break
        }
    }

    private func transitionToBuffering() {
        playbackState = .buffering
        scheduleBufferingTimeout()
    }

    private func transitionToError(_ message: String) {
        cancelBufferingTimeout()
        playbackState = .error(message)
        driver.stop()
    }

    private func scheduleBufferingTimeout() {
        cancelBufferingTimeout()
        bufferingTimeoutTask = timeoutScheduler.schedule(after: bufferingTimeout) { [weak self] in
            guard let self else { return }
            if self.playbackState == .buffering {
                self.transitionToError(
                    MusicError.streamFailed(reason: "Playback timed out while buffering.").userMessage
                )
            }
        }
    }

    private func cancelBufferingTimeout() {
        bufferingTimeoutTask?.cancel()
        bufferingTimeoutTask = nil
    }

    private func logPlaybackFailureIfNeeded(reason: String) {
        guard !hasLoggedFailureForActivePlayback else { return }
        hasLoggedFailureForActivePlayback = true

        diagnosticsLogger.logPlaybackFailure(
            reason: reason,
            sanitizedURLContext: sanitizeURLContext(activePlaybackURL)
        )
    }

    private func sanitizeURLContext(_ url: URL?) -> String {
        guard let url else { return "unknown" }

        if let host = url.host {
            return host + url.path
        }

        return url.path.isEmpty ? "unknown" : url.path
    }
}
