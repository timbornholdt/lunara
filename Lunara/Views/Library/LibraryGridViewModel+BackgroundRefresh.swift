import Foundation

extension LibraryGridViewModel {
    func applyBackgroundRefreshUpdateIfNeeded(successToken: Int) async {
        guard successToken > 0 else {
            return
        }

        guard loadingState != .loading else {
            return
        }

        await reloadCachedCatalogForBackgroundUpdate()
    }

    func applyBackgroundRefreshFailureIfNeeded(failureToken: Int, message: String?) {
        guard failureToken > 0 else {
            return
        }

        guard let message, !message.isEmpty else {
            return
        }

        errorBannerState.show(message: message)
    }

    private func reloadCachedCatalogForBackgroundUpdate() async {
        do {
            albums = try await library.queryAlbums(filter: .all)
            await refreshSearchResultsIfNeeded()
            loadingState = .loaded
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }
}
