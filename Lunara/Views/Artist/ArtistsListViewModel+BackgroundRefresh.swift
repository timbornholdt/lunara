import Foundation

extension ArtistsListViewModel {
    func applyBackgroundRefreshUpdateIfNeeded(successToken: Int) async {
        guard successToken > 0 else {
            return
        }

        guard loadingState != .loading else {
            return
        }

        await reloadArtistsForBackgroundUpdate()
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

    private func reloadArtistsForBackgroundUpdate() async {
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
