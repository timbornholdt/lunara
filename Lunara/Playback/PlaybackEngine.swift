import Foundation

final class PlaybackEngine: PlaybackEngineing {
    var onStateChange: ((NowPlayingState?) -> Void)?
    var onError: ((PlaybackError) -> Void)?

    private let player: PlaybackPlayer
    private let sourceResolver: PlaybackSourceResolving
    private let fallbackURLBuilder: PlaybackFallbackURLBuilding
    private let audioSession: AudioSessionManaging

    private var queueItems: [PlaybackQueueItem] = []
    private var currentIndex = 0
    private var currentElapsed: TimeInterval = 0
    private var isPlaying = false

    init(
        player: PlaybackPlayer = AVQueuePlayerAdapter(),
        sourceResolver: PlaybackSourceResolving,
        fallbackURLBuilder: PlaybackFallbackURLBuilding,
        audioSession: AudioSessionManaging = AudioSessionManager()
    ) {
        self.player = player
        self.sourceResolver = sourceResolver
        self.fallbackURLBuilder = fallbackURLBuilder
        self.audioSession = audioSession
        bindPlayerCallbacks()
    }

    func play(tracks: [PlexTrack], startIndex: Int) {
        guard !tracks.isEmpty else {
            onError?(PlaybackError(message: "Playback unavailable for this track."))
            return
        }
        let start: Int
        if startIndex < 0 || startIndex >= tracks.count {
            start = 0
        } else {
            start = startIndex
        }
        let slicedTracks = Array(tracks[start...])
        let items = slicedTracks.compactMap { track -> PlaybackQueueItem? in
            guard let source = sourceResolver.resolveSource(for: track) else { return nil }
            let fallback: URL?
            switch source {
            case .remote:
                fallback = fallbackURLBuilder.makeTranscodeURL(trackRatingKey: track.ratingKey)
            case .local:
                fallback = nil
            }
            return PlaybackQueueItem(track: track, primaryURL: source.url, fallbackURL: fallback)
        }
        guard !items.isEmpty else {
            onError?(PlaybackError(message: "Playback unavailable for this track."))
            return
        }
        do {
            try audioSession.configureForPlayback()
        } catch {
            onError?(PlaybackError(message: "Playback failed."))
            return
        }

        queueItems = items
        currentIndex = 0
        currentElapsed = 0
        player.setQueue(urls: items.map { $0.primaryURL })
        player.play()
        isPlaying = true
        publishState()
    }

    func stop() {
        player.stop()
        queueItems.removeAll()
        currentIndex = 0
        currentElapsed = 0
        isPlaying = false
        onStateChange?(nil)
    }

    private func bindPlayerCallbacks() {
        player.onItemChanged = { [weak self] index in
            self?.handleItemChanged(index: index)
        }
        player.onItemFailed = { [weak self] index in
            self?.handleItemFailure(index: index)
        }
        player.onTimeUpdate = { [weak self] time in
            self?.handleTimeUpdate(time)
        }
        player.onPlaybackStateChanged = { [weak self] playing in
            self?.handlePlaybackStateChange(isPlaying: playing)
        }
    }

    private func handleItemChanged(index: Int) {
        guard index >= 0, index < queueItems.count else { return }
        currentIndex = index
        currentElapsed = 0
        publishState()
    }

    private func handleItemFailure(index: Int) {
        guard index >= 0, index < queueItems.count else { return }
        if queueItems[index].didUseFallback {
            onError?(PlaybackError(message: "Playback failed."))
            return
        }
        guard let fallbackURL = queueItems[index].fallbackURL else {
            onError?(PlaybackError(message: "Playback failed."))
            return
        }
        queueItems[index].didUseFallback = true
        player.replaceCurrentItem(url: fallbackURL)
    }

    private func handleTimeUpdate(_ time: TimeInterval) {
        currentElapsed = time
        publishState()
    }

    private func handlePlaybackStateChange(isPlaying: Bool) {
        self.isPlaying = isPlaying
        publishState()
    }

    private func publishState() {
        guard !queueItems.isEmpty, currentIndex < queueItems.count else {
            onStateChange?(nil)
            return
        }
        let item = queueItems[currentIndex]
        let durationSeconds = item.track.duration.map { Double($0) / 1000.0 }
        let trackIndex = item.track.index ?? (currentIndex + 1)
        let state = NowPlayingState(
            trackTitle: item.track.title,
            artistName: nil,
            isPlaying: isPlaying,
            trackIndex: trackIndex,
            elapsedTime: currentElapsed,
            duration: durationSeconds
        )
        onStateChange?(state)
    }
}

private struct PlaybackQueueItem {
    let track: PlexTrack
    let primaryURL: URL
    let fallbackURL: URL?
    var didUseFallback = false
}
