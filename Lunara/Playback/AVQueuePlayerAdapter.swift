import AVFoundation

final class AVQueuePlayerAdapter: PlaybackPlayer {
    var onItemChanged: ((Int) -> Void)?
    var onItemFailed: ((Int) -> Void)?
    var onTimeUpdate: ((TimeInterval) -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?

    let player: AVQueuePlayer

    private var items: [AVPlayerItem] = []
    private var itemIndex: [ObjectIdentifier: Int] = [:]
    private var currentIndex = 0
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?

    init(player: AVQueuePlayer = AVQueuePlayer()) {
        self.player = player
        player.automaticallyWaitsToMinimizeStalling = true
        bindPlayerObservers()
    }

    deinit {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
        }
    }

    func setQueue(urls: [URL]) {
        player.removeAllItems()
        items = urls.map { AVPlayerItem(url: $0) }
        itemIndex = Dictionary(uniqueKeysWithValues: items.enumerated().map { (ObjectIdentifier($0.element), $0.offset) })
        for item in items {
            player.insert(item, after: nil)
        }
        currentIndex = 0
        if !items.isEmpty {
            onItemChanged?(0)
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.pause()
        player.removeAllItems()
        items.removeAll()
        itemIndex.removeAll()
        currentIndex = 0
    }

    func replaceCurrentItem(url: URL) {
        guard currentIndex >= 0, currentIndex < items.count else { return }
        let newItem = AVPlayerItem(url: url)
        items[currentIndex] = newItem
        itemIndex[ObjectIdentifier(newItem)] = currentIndex
        player.replaceCurrentItem(with: newItem)
    }

    func seek(to seconds: TimeInterval) {
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        player.seek(to: time)
    }

    private func bindPlayerObservers() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleItemDidEnd(notification)
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleItemFailed(notification)
        }
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.onTimeUpdate?(time.seconds)
        }
        statusObserver = player.observe(\AVQueuePlayer.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            self?.onPlaybackStateChanged?(player.timeControlStatus == .playing)
        }
    }

    private func handleItemDidEnd(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem,
              let index = itemIndex[ObjectIdentifier(item)],
              index == currentIndex else { return }
        player.advanceToNextItem()
        currentIndex = min(currentIndex + 1, items.count)
        if currentIndex < items.count {
            onItemChanged?(currentIndex)
        }
    }

    private func handleItemFailed(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem,
              let index = itemIndex[ObjectIdentifier(item)] else { return }
        onItemFailed?(index)
    }
}
