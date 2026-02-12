import Foundation

final class OfflineServices {
    static let shared = OfflineServices()

    let manifestStore: OfflineManifestStore
    let fileStore: OfflineFileStore
    let playbackIndex: OfflinePlaybackIndex
    let coordinator: OfflineDownloadsCoordinator

    private let wifiMonitor: WiFiReachabilityMonitor

    init(
        manifestStore: OfflineManifestStore = OfflineManifestStore(),
        fileStore: OfflineFileStore = OfflineFileStore(),
        playbackIndex: OfflinePlaybackIndex? = nil,
        wifiMonitor: WiFiReachabilityMonitor = WiFiReachabilityMonitor(),
        trackFetcher: OfflineTrackFetching = AppOfflineTrackFetcher(),
        downloader: OfflineTrackDownloading = AppOfflineTrackDownloader()
    ) {
        self.manifestStore = manifestStore
        self.fileStore = fileStore
        if let manifest = try? manifestStore.load(),
           manifest.containsLegacyAudioFiles {
            try? fileStore.removeAll()
            try? manifestStore.clear()
        }
        let resolvedPlaybackIndex = playbackIndex ?? OfflinePlaybackIndex(
            manifestStore: manifestStore,
            fileStore: fileStore
        )
        self.playbackIndex = resolvedPlaybackIndex
        self.wifiMonitor = wifiMonitor
        self.wifiMonitor.start()
        self.coordinator = OfflineDownloadsCoordinator.make(
            manifestStore: manifestStore,
            fileStore: fileStore,
            trackFetcher: trackFetcher,
            downloader: downloader,
            wifiMonitor: wifiMonitor
        )
    }
}
