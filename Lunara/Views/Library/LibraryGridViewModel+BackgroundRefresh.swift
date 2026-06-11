import Foundation

extension LibraryGridViewModel: BackgroundRefreshApplying {
    var isLoadingForBackgroundRefresh: Bool {
        loadingState == .loading
    }

    func reloadForBackgroundUpdate() async {
        do {
            // Preserve the user's loaded scroll depth instead of collapsing to one page.
            try await replaceCatalog(limit: reloadLimit)
            await refreshSearchResultsIfNeeded()
            loadingState = .loaded
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }
}
