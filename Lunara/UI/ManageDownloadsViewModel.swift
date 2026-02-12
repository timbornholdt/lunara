import Combine
import Foundation

@MainActor
final class ManageDownloadsViewModel: ObservableObject {
    @Published private(set) var snapshot = OfflineManageDownloadsSnapshot(
        queue: OfflineDownloadQueueSnapshot(pendingTracks: [], inProgressTracks: []),
        downloadedAlbums: [],
        downloadedCollections: [],
        streamCachedTracks: []
    )
    @Published var errorMessage: String?
    @Published private(set) var albumsByRatingKey: [String: PlexAlbum] = [:]
    @Published private(set) var collectionsByKey: [String: PlexCollection] = [:]
    @Published private(set) var musicSectionKey: String?

    private let coordinator: OfflineDownloadsCoordinator
    private let snapshotStore: LibrarySnapshotStoring
    private var cancellables: Set<AnyCancellable> = []

    init(
        coordinator: OfflineDownloadsCoordinator? = nil,
        snapshotStore: LibrarySnapshotStoring = LibrarySnapshotStore()
    ) {
        self.coordinator = coordinator ?? OfflineServices.shared.coordinator
        self.snapshotStore = snapshotStore
        NotificationCenter.default.publisher(for: .offlineDownloadsDidChange)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.load()
                }
            }
            .store(in: &cancellables)
    }

    func load() async {
        snapshot = await coordinator.manageDownloadsSnapshot()
        if let librarySnapshot = try? snapshotStore.load() {
            albumsByRatingKey = Dictionary(
                uniqueKeysWithValues: librarySnapshot.albums.map { album in
                    (album.ratingKey, album.toPlexAlbum())
                }
            )
            collectionsByKey = Dictionary(
                uniqueKeysWithValues: librarySnapshot.collections.map { collection in
                    (collection.ratingKey, collection.toPlexCollection())
                }
            )
            musicSectionKey = librarySnapshot.musicSectionKey
        }
    }

    func cancel(trackRatingKey: String) async {
        do {
            try await coordinator.cancelTrackDownload(trackRatingKey: trackRatingKey)
            snapshot = await coordinator.manageDownloadsSnapshot()
        } catch {
            errorMessage = "Failed to cancel download."
        }
    }

    func removeAlbum(albumIdentity: String) async {
        do {
            try await coordinator.removeAlbumDownload(albumIdentity: albumIdentity)
            snapshot = await coordinator.manageDownloadsSnapshot()
        } catch {
            errorMessage = "Failed to remove album download."
        }
    }

    func removeCollection(collectionKey: String) async {
        do {
            try await coordinator.removeCollectionDownload(collectionKey: collectionKey)
            snapshot = await coordinator.manageDownloadsSnapshot()
        } catch {
            errorMessage = "Failed to remove collection download."
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
