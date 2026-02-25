import AVFoundation
import Foundation

protocol PlaybackEngineDriver: AnyObject {
    var onTimeControlStatusChanged: ((AVPlayer.TimeControlStatus) -> Void)? { get set }
    var onCurrentTrackIDChanged: ((String?) -> Void)? { get set }
    var onCurrentItemFailed: ((String) -> Void)? { get set }
    var onCurrentItemEnded: (() -> Void)? { get set }
    var onElapsedChanged: ((TimeInterval) -> Void)? { get set }
    var onDurationChanged: ((TimeInterval) -> Void)? { get set }

    func play(url: URL, trackID: String)
    func pause()
    func resume()
    func seek(to time: TimeInterval)
    func stop()
}

final class AVQueuePlayerDriver: PlaybackEngineDriver {
    var onTimeControlStatusChanged: ((AVPlayer.TimeControlStatus) -> Void)?
    var onCurrentTrackIDChanged: ((String?) -> Void)?
    var onCurrentItemFailed: ((String) -> Void)?
    var onCurrentItemEnded: (() -> Void)?
    var onElapsedChanged: ((TimeInterval) -> Void)?
    var onDurationChanged: ((TimeInterval) -> Void)?

    private let player: AVQueuePlayer
    private let notificationCenter: NotificationCenterType

    private var timeControlObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var currentItemStatusObservation: NSKeyValueObservation?

    private var didPlayToEndObserver: NSObjectProtocol?
    private var failedToPlayToEndObserver: NSObjectProtocol?
    private var playbackStalledObserver: NSObjectProtocol?
    private var timeObserverToken: Any?

    private var trackIDsByItemIdentifier: [ObjectIdentifier: String] = [:]

    init(
        player: AVQueuePlayer = AVQueuePlayer(),
        notificationCenter: NotificationCenterType = NotificationCenter.default
    ) {
        self.player = player
        self.notificationCenter = notificationCenter
        configureObservers()
    }

    deinit {
        if let didPlayToEndObserver {
            notificationCenter.removeObserver(didPlayToEndObserver)
        }

        if let failedToPlayToEndObserver {
            notificationCenter.removeObserver(failedToPlayToEndObserver)
        }

        if let playbackStalledObserver {
            notificationCenter.removeObserver(playbackStalledObserver)
        }

        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
    }

    func play(url: URL, trackID: String) {
        let item = makePlayerItem(url: url, trackID: trackID)
        player.removeAllItems()
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func pause() {
        player.pause()
    }

    func resume() {
        player.play()
    }

    func seek(to time: TimeInterval) {
        let clampedSeconds = max(0, time)
        let targetTime = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        player.seek(to: targetTime)
    }

    func stop() {
        player.pause()
        player.removeAllItems()
        player.replaceCurrentItem(with: nil)
        onCurrentTrackIDChanged?(nil)
        onElapsedChanged?(0)
        onDurationChanged?(0)
    }

    private func configureObservers() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            self?.onTimeControlStatusChanged?(player.timeControlStatus)
        }

        currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            self?.handleCurrentItemChanged(player.currentItem)
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let elapsedSeconds = max(0, time.seconds)
            if elapsedSeconds.isFinite {
                self.onElapsedChanged?(elapsedSeconds)
            }
        }

        didPlayToEndObserver = notificationCenter.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let item = notification.object as? AVPlayerItem,
                item == self.player.currentItem
            else {
                return
            }
            self.onCurrentItemEnded?()
        }

        failedToPlayToEndObserver = notificationCenter.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard notification.object as? AVPlayerItem != nil else { return }
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            let message = error?.localizedDescription ?? MusicError.streamFailed(reason: "Stream failed.").userMessage
            self?.onCurrentItemFailed?(message)
        }

        playbackStalledObserver = notificationCenter.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let item = notification.object as? AVPlayerItem,
                item == self.player.currentItem
            else {
                return
            }

            self.onCurrentItemFailed?(MusicError.streamFailed(reason: "Playback stalled.").userMessage)
        }
    }

    private func handleCurrentItemChanged(_ item: AVPlayerItem?) {
        currentItemStatusObservation = nil

        guard let item else {
            onCurrentTrackIDChanged?(nil)
            onDurationChanged?(0)
            return
        }

        onCurrentTrackIDChanged?(trackIDsByItemIdentifier[ObjectIdentifier(item)])
        publishDuration(from: item.duration)

        currentItemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }

            switch item.status {
            case .readyToPlay:
                self.publishDuration(from: item.duration)
            case .failed:
                let message = item.error?.localizedDescription
                    ?? MusicError.streamFailed(reason: "Unable to play this stream.").userMessage
                self.onCurrentItemFailed?(message)
            case .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    private func makePlayerItem(url: URL, trackID: String) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        trackIDsByItemIdentifier[ObjectIdentifier(item)] = trackID
        return item
    }

    private func publishDuration(from time: CMTime) {
        let seconds = time.seconds
        if seconds.isFinite && !seconds.isNaN && seconds >= 0 {
            onDurationChanged?(seconds)
        } else {
            onDurationChanged?(0)
        }
    }
}

