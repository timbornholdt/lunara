import Foundation

enum PlaybackSource: Equatable {
    case remote(url: URL)
    case local(fileURL: URL)

    var url: URL {
        switch self {
        case .remote(let url):
            return url
        case .local(let url):
            return url
        }
    }
}

protocol LocalPlaybackIndexing {
    func fileURL(for trackKey: String) -> URL?
    func markPlayed(trackKey: String, at date: Date)
}

extension LocalPlaybackIndexing {
    func markPlayed(trackKey: String, at date: Date) {
    }
}

protocol NetworkReachabilityMonitoring {
    var isReachable: Bool { get }
}

protocol PlaybackSourceResolving {
    func resolveSource(for track: PlexTrack) -> PlaybackSource?
}

struct PlaybackSourceResolver: PlaybackSourceResolving {
    let localIndex: LocalPlaybackIndexing?
    let urlBuilder: PlexPlaybackURLBuilder
    let networkMonitor: NetworkReachabilityMonitoring?

    init(
        localIndex: LocalPlaybackIndexing?,
        urlBuilder: PlexPlaybackURLBuilder,
        networkMonitor: NetworkReachabilityMonitoring? = nil
    ) {
        self.localIndex = localIndex
        self.urlBuilder = urlBuilder
        self.networkMonitor = networkMonitor
    }

    func resolveSource(for track: PlexTrack) -> PlaybackSource? {
        log("resolveSource track=\(track.ratingKey) title=\(track.title)")
        if let fileURL = localIndex?.fileURL(for: track.ratingKey) {
            log("using local source track=\(track.ratingKey) url=\(fileURL.path)")
            return .local(fileURL: fileURL)
        }
        if let networkMonitor, networkMonitor.isReachable == false {
            log("no source track=\(track.ratingKey) reason=network_unreachable")
            return nil
        }
        guard let partKey = track.media?.first?.parts.first?.key else { return nil }
        let remoteURL = urlBuilder.makeDirectPlayURL(partKey: partKey)
        log("using remote source track=\(track.ratingKey) partKey=\(partKey)")
        return .remote(url: remoteURL)
    }

    private func log(_ message: String) {
#if DEBUG
        print("[PlaybackDebug][Resolver] \(message)")
#endif
    }
}
