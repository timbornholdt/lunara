import SwiftUI
import os

extension DebugLibraryView {
    func fetchAlbumsOnLaunch() {
        loadAlbums(
            logMessage: "Fetch albums requested for app launch from debug screen",
            loader: { try await coordinator.loadLibraryOnLaunch() }
        )
    }

    func refreshAlbumsUserInitiated() {
        loadAlbums(
            logMessage: "Fetch albums requested from debug screen",
            loader: { try await coordinator.fetchAlbums() }
        )
    }

    @MainActor
    func applyBackgroundRefreshIfNeeded() async {
        guard coordinator.backgroundRefreshSuccessToken > 0 else {
            return
        }

        do {
            let refreshedAlbums = try await coordinator.libraryRepo.fetchAlbums()
            albums = refreshedAlbums
            errorMessage = nil
            logger.info("Applied background refresh update in debug view with \(refreshedAlbums.count, privacy: .public) cached albums")
        } catch let error as LunaraError {
            errorBannerState.show(message: error.userMessage)
            logger.error("Failed to apply background refresh update in debug view. Error: \(String(describing: error), privacy: .public)")
        } catch {
            errorBannerState.show(message: error.localizedDescription)
            logger.error("Failed to apply background refresh update in debug view with unexpected error: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    func applyBackgroundRefreshFailureIfNeeded() {
        guard coordinator.backgroundRefreshFailureToken > 0 else {
            return
        }

        guard let message = coordinator.lastBackgroundRefreshErrorMessage,
              !message.isEmpty else {
            return
        }

        logger.info("Displaying background refresh failure banner in debug view")
        errorBannerState.show(message: message)
    }

    func loadAlbums(
        logMessage: String,
        loader: @escaping @MainActor () async throws -> [Album]
    ) {
        logger.info("\(logMessage, privacy: .public)")
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetchedAlbums = try await loader()
                await MainActor.run {
                    albums = fetchedAlbums
                    isLoading = false
                }
                logger.info("Fetched \(fetchedAlbums.count, privacy: .public) albums")
                duplicateReporter.logReport(
                    albums: fetchedAlbums,
                    logger: logger,
                    spotlightTitle: "After the Gold Rush",
                    spotlightArtist: "Neil Young"
                )
            } catch let error as LibraryError {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.userMessage
                }
                logger.error("Fetch albums failed with LibraryError: \(String(describing: error), privacy: .public)")
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
                logger.error("Fetch albums failed with unexpected error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func playAlbum(_ album: Album) {
        logger.info("Play tapped for album '\(album.title, privacy: .public)' with plexID '\(album.plexID, privacy: .public)'")
        Task {
            do {
                let tracks = try await coordinator.libraryRepo.tracks(forAlbum: album.plexID)
                await MainActor.run {
                    for track in tracks {
                        tracksByID[track.plexID] = track
                    }
                }
                try await coordinator.playAlbum(album)
                logger.info("Play request succeeded for album '\(album.title, privacy: .public)'")
            } catch let error as LunaraError {
                await MainActor.run {
                    errorMessage = error.userMessage
                }
                logger.error("Play request failed for album '\(album.title, privacy: .public)'. Error: \(String(describing: error), privacy: .public)")
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
                logger.error("Play request failed for album '\(album.title, privacy: .public)' with unexpected error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func showTestBanner() {
        let message = "Debug banner test: tap again to retrigger."
        logger.info("Showing debug error banner test message")
        errorBannerState.show(message: message)
    }
}
