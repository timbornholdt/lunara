import Foundation

extension CollectionsListViewModel: BackgroundRefreshApplying {
    var isLoadingForBackgroundRefresh: Bool {
        loadingState == .loading
    }

    func reloadForBackgroundUpdate() async {
        do {
            let allCollections = try await library.collections()
            collections = allCollections.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            loadingState = .loaded
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }
}
