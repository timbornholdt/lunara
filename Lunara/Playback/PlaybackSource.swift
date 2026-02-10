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
}

protocol PlaybackSourceResolving {
    func resolveSource(for track: PlexTrack) -> PlaybackSource?
}

struct PlaybackSourceResolver: PlaybackSourceResolving {
    let localIndex: LocalPlaybackIndexing?
    let urlBuilder: PlexPlaybackURLBuilder

    func resolveSource(for track: PlexTrack) -> PlaybackSource? {
        if let fileURL = localIndex?.fileURL(for: track.ratingKey) {
            return .local(fileURL: fileURL)
        }
        guard let partKey = track.media?.first?.parts.first?.key else { return nil }
        return .remote(url: urlBuilder.makeDirectPlayURL(partKey: partKey))
    }
}
