import Foundation

enum AlbumDownloadState: Equatable, Sendable {
    case idle
    case downloading(completedTracks: Int, totalTracks: Int)
    case complete
    case failed(String)
}

@MainActor
protocol DownloadManagerProtocol: AnyObject {
    /// Current download state for an album (in-memory only).
    func downloadState(forAlbum albumID: String) -> AlbumDownloadState

    /// Resolved download state: checks in-memory state first, then falls back to the offline store DB.
    func resolvedDownloadState(forAlbum albumID: String, totalTrackCount: Int) async -> AlbumDownloadState

    /// Downloads all tracks for an album. Foreground-only, sequential.
    func downloadAlbum(_ album: Album, tracks: [Track]) async

    /// Cancels an in-progress download for an album.
    func cancelDownload(forAlbum albumID: String)

    /// Removes all downloaded files for an album.
    func removeDownload(forAlbum albumID: String) async throws

    /// Syncs a collection: marks it for sync, downloads new albums, removes stale ones.
    func syncCollection(_ collectionID: String, albums: [Album], library: LibraryRepoProtocol) async

    /// Removes the sync marker and deletes orphaned downloads.
    func unsyncCollection(_ collectionID: String, library: LibraryRepoProtocol) async
}
