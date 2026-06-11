import Foundation

extension ArtistsListViewModel: BackgroundRefreshApplying {
    var isLoadingForBackgroundRefresh: Bool {
        loadingState == .loading
    }

    func reloadForBackgroundUpdate() async {
        do {
            let allArtists = try await library.artists()
            artists = allArtists.sorted {
                $0.effectiveSortName.localizedCaseInsensitiveCompare($1.effectiveSortName) == .orderedAscending
            }
            loadingState = .loaded
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }
}
