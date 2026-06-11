import Foundation

extension LibraryGridViewModel: BackgroundRefreshApplying {
    var isLoadingForBackgroundRefresh: Bool {
        loadingState == .loading
    }

    func reloadForBackgroundUpdate() async {
        do {
            try await replaceCatalog()
            await refreshSearchResultsIfNeeded()
            loadingState = .loaded
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }
}
