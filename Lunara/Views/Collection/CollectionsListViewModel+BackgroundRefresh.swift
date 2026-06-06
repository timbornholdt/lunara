import Foundation

extension CollectionsListViewModel {
    func applyBackgroundRefreshUpdateIfNeeded(successToken: Int) async {
        guard successToken > 0 else {
            return
        }

        guard loadingState != .loading else {
            return
        }

        await reloadCollectionsForBackgroundUpdate()
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

    private func reloadCollectionsForBackgroundUpdate() async {
        do {
            let allCollections = try await library.collections()
            collections = allCollections.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            loadingState = .loaded
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }
}
