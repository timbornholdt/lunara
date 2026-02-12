import Foundation

extension Notification.Name {
    static let offlineDownloadsDidChange = Notification.Name("offlineDownloadsDidChange")
}

enum OfflineDownloadSource: Equatable, Sendable {
    case explicitAlbum
    case collection(String)
    case opportunistic

    var isOpportunistic: Bool {
        switch self {
        case .opportunistic:
            return true
        default:
            return false
        }
    }
}

struct OfflineDownloadedPayload: Sendable {
    let data: Data
    let expectedBytes: Int64?
    let suggestedFileExtension: String?

    var actualBytes: Int64 {
        Int64(data.count)
    }
}

protocol OfflineTrackFetching {
    func fetchMergedTracks(albumRatingKeys: [String]) async throws -> [PlexTrack]
}

protocol OfflineTrackDownloading {
    func downloadTrack(
        trackRatingKey: String,
        partKey: String,
        progress: @escaping @Sendable (_ bytesReceived: Int64, _ expectedBytes: Int64?) -> Void
    ) async throws -> OfflineDownloadedPayload
}

protocol WiFiReachabilityMonitoring: AnyObject {
    var isOnWiFi: Bool { get }
    func setOnWiFiChangeHandler(_ handler: (@Sendable (Bool) -> Void)?)
}

protocol OfflineOpportunisticCaching: AnyObject {
    func enqueueOpportunistic(current: PlexTrack, upcoming: [PlexTrack], limit: Int) async
}

protocol OfflineDownloadQueuing: AnyObject {
    func enqueueAlbumDownload(
        albumIdentity: String,
        displayTitle: String,
        artistName: String?,
        artworkPath: String?,
        albumRatingKeys: [String],
        source: OfflineDownloadSource
    ) async throws

    func upsertCollectionRecord(
        collectionKey: String,
        title: String,
        albumIdentities: [String]
    ) async throws

    func downloadedCollectionKeys() async -> [String]

    func reconcileCollectionDownload(
        collectionKey: String,
        title: String,
        albumGroups: [OfflineCollectionAlbumGroup]
    ) async throws

    func removeCollectionDownload(collectionKey: String) async throws
}

protocol OfflineDownloadStatusProviding: AnyObject {
    func albumDownloadProgress(albumIdentity: String) async -> OfflineAlbumDownloadProgress?
}

protocol OfflineDownloadsLifecycleManaging: AnyObject {
    func purgeAll() async throws
}

enum OfflineDownloadError: Error, Equatable {
    case missingTrackPartKey(String)
    case incompleteDownload(String)
    case insufficientStorageNonEvictable
}

enum OfflineRuntimeError: Error, Equatable {
    case missingServerURL
    case missingAuthToken
    case unexpectedHTTPStatus(Int)
}

struct OfflineTrackProgress: Equatable, Sendable {
    let trackRatingKey: String
    let trackTitle: String?
    let albumIdentity: String?
    let albumTitle: String?
    let artistName: String?
    let artworkPath: String?
    let bytesReceived: Int64
    let expectedBytes: Int64?
    let bytesPerSecond: Double?
    let estimatedRemainingSeconds: TimeInterval?
}

struct OfflineDownloadQueueSnapshot: Equatable, Sendable {
    let pendingTracks: [OfflineTrackProgress]
    let inProgressTracks: [OfflineTrackProgress]

    var pendingTrackKeys: [String] {
        pendingTracks.map(\.trackRatingKey)
    }

    var pendingCount: Int {
        pendingTracks.count
    }

    var inProgressCount: Int {
        inProgressTracks.count
    }
}

struct OfflineDownloadedAlbumSummary: Equatable, Sendable, Identifiable {
    let albumIdentity: String
    let displayTitle: String
    let artistName: String?
    let artworkPath: String?
    let albumRatingKeys: [String]
    let completedTrackCount: Int
    let totalTrackCount: Int
    let collectionMembershipCount: Int

    var id: String {
        albumIdentity
    }
}

struct OfflineDownloadedCollectionSummary: Equatable, Sendable, Identifiable {
    let collectionKey: String
    let title: String
    let albumCount: Int

    var id: String {
        collectionKey
    }
}

struct OfflineStreamCachedTrackSummary: Equatable, Sendable, Identifiable {
    let trackRatingKey: String
    let albumIdentity: String?
    let completedAt: Date?

    var id: String {
        trackRatingKey
    }
}

struct OfflineManageDownloadsSnapshot: Equatable, Sendable {
    let queue: OfflineDownloadQueueSnapshot
    let downloadedAlbums: [OfflineDownloadedAlbumSummary]
    let downloadedCollections: [OfflineDownloadedCollectionSummary]
    let streamCachedTracks: [OfflineStreamCachedTrackSummary]
}

struct OfflineCollectionAlbumGroup: Equatable, Sendable {
    let albumIdentity: String
    let displayTitle: String
    let artistName: String?
    let artworkPath: String?
    let albumRatingKeys: [String]

    init(
        albumIdentity: String,
        displayTitle: String,
        artistName: String? = nil,
        artworkPath: String? = nil,
        albumRatingKeys: [String]
    ) {
        self.albumIdentity = albumIdentity
        self.displayTitle = displayTitle
        self.artistName = artistName
        self.artworkPath = artworkPath
        self.albumRatingKeys = albumRatingKeys
    }
}

struct OfflineAlbumDownloadProgress: Equatable, Sendable {
    let albumIdentity: String
    let totalTrackCount: Int
    let completedTrackCount: Int
    let pendingTrackCount: Int
    let inProgressTrackCount: Int
    let partialInProgressTrackUnits: Double

    var hasActiveWork: Bool {
        pendingTrackCount > 0 || inProgressTrackCount > 0
    }

    var isComplete: Bool {
        totalTrackCount > 0 && completedTrackCount >= totalTrackCount && hasActiveWork == false
    }

    var fractionComplete: Double {
        guard totalTrackCount > 0 else { return 0 }
        let units = Double(completedTrackCount) + partialInProgressTrackUnits
        return min(max(units / Double(totalTrackCount), 0), 1)
    }
}
