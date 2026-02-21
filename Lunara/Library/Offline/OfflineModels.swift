import Foundation

struct OfflineTrack: Equatable, Sendable {
    let trackID: String
    let albumID: String
    let filename: String
    let downloadedAt: Date
    let fileSizeBytes: Int64
}

enum OfflineAlbumStatus: Equatable, Sendable {
    case notDownloaded
    case partiallyDownloaded(downloadedCount: Int, totalCount: Int)
    case downloaded
}
