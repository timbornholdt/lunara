import Foundation

extension PlaylistsListViewModel: BackgroundRefreshApplying {
    var isLoadingForBackgroundRefresh: Bool {
        loadingState == .loading
    }

    func reloadForBackgroundUpdate() async {
        do {
            let snapshots = try await library.playlists()
            playlists = snapshots
                .map(Playlist.init(snapshot:))
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            loadingState = .loaded
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }
}
