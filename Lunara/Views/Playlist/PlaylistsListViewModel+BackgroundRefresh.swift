import Foundation

extension PlaylistsListViewModel {
    func applyBackgroundRefreshUpdateIfNeeded(successToken: Int) async {
        guard successToken > 0 else {
            return
        }

        guard loadingState != .loading else {
            return
        }

        await reloadPlaylistsForBackgroundUpdate()
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

    private func reloadPlaylistsForBackgroundUpdate() async {
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
