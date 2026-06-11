import Foundation
import os

/// Owns the library refresh lifecycle — cached-first loads with background
/// refresh, refresh status reporting, queue reconciliation after catalog
/// changes, and synced-collection reconciliation. Extracted from
/// AppCoordinator (Lunara-uww.5.3); the coordinator delegates to it.
@MainActor
final class LibraryRefreshService {
    /// Observable refresh status consumed by the list views' background-refresh
    /// hooks (Lunara-uww.5.2).
    let status = RefreshStatusService()

    private let library: LibraryRepoProtocol
    private let appRouter: AppRouter
    private let offlineStore: OfflineStoreProtocol
    private let downloadManager: DownloadManager
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "LibraryRefreshService")

    init(
        library: LibraryRepoProtocol,
        appRouter: AppRouter,
        offlineStore: OfflineStoreProtocol,
        downloadManager: DownloadManager
    ) {
        self.library = library
        self.appRouter = appRouter
        self.offlineStore = offlineStore
        self.downloadManager = downloadManager
    }

    /// Cached-first: returns cached albums immediately and refreshes in the
    /// background; with an empty cache, refreshes in the foreground.
    func syncAlbums(refreshReason: LibraryRefreshReason) async throws -> [Album] {
        let cachedAlbums = try await library.fetchAlbums()

        if !cachedAlbums.isEmpty {
            if refreshReason == .appLaunch {
                Task { [weak self] in
                    guard let self else {
                        return
                    }
                    await self.reconcileQueueAfterCatalogUpdate(trigger: "startup-cache-load")
                }
            }

            Task { [weak self] in
                guard let self else {
                    return
                }
                await self.performBackgroundRefresh(reason: refreshReason)
            }
            return cachedAlbums
        }

        do {
            let outcome = try await library.refreshLibrary(reason: refreshReason)
            status.recordSuccess(at: outcome.refreshedAt)
        } catch let error as LunaraError {
            status.recordFailure(message: error.userMessage)
            throw error
        } catch {
            status.recordFailure(message: error.localizedDescription)
            throw error
        }
        await reconcileQueueAfterCatalogUpdate(trigger: "foreground-refresh-\(String(describing: refreshReason))")
        return try await library.fetchAlbums()
    }

    /// Reconciles all synced collections against their current album lists.
    /// Called on app launch after library refresh.
    func syncAllCollections() async {
        do {
            let syncedIDs = try await offlineStore.syncedCollectionIDs()
            guard !syncedIDs.isEmpty else { return }

            logger.info("syncAllCollections: reconciling \(syncedIDs.count) synced collections")
            for collectionID in syncedIDs {
                do {
                    let albums = try await library.collectionAlbums(collectionID: collectionID)
                    await downloadManager.syncCollection(collectionID, albums: albums, library: library)
                } catch {
                    logger.warning("syncAllCollections: failed to sync collection '\(collectionID, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            logger.warning("syncAllCollections: failed to load synced collection IDs: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func performBackgroundRefresh(reason: LibraryRefreshReason) async {
        do {
            let outcome = try await library.refreshLibrary(reason: reason)
            status.recordSuccess(at: outcome.refreshedAt)
            logger.info("Background refresh succeeded for reason '\(String(describing: reason), privacy: .public)' at \(outcome.refreshedAt, privacy: .public)")

            if reason == .appLaunch {
                await syncAllCollections()
            } else {
                await reconcileQueueAfterCatalogUpdate(trigger: "background-refresh-\(String(describing: reason))")
            }
        } catch let error as LunaraError {
            status.recordFailure(message: error.userMessage)
            logger.error("Background refresh failed for reason '\(String(describing: reason), privacy: .public)' with LunaraError: \(String(describing: error), privacy: .public)")
        } catch {
            status.recordFailure(message: error.localizedDescription)
            logger.error("Background refresh failed for reason '\(String(describing: reason), privacy: .public)' with unexpected error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reconcileQueueAfterCatalogUpdate(trigger: String) async {
        do {
            let outcome = try await appRouter.reconcileQueueAgainstLibrary()
            guard outcome.removedItemCount > 0 else {
                logger.info("Queue reconciliation found no missing tracks for trigger '\(trigger, privacy: .public)'")
                return
            }

            logger.info(
                "Queue reconciliation removed \(outcome.removedItemCount, privacy: .public) queue items for trigger '\(trigger, privacy: .public)'"
            )
        } catch {
            logger.error("Queue reconciliation failed for trigger '\(trigger, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        }
    }
}
