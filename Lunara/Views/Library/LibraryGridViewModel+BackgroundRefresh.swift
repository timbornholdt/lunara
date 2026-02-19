import Foundation

extension LibraryGridViewModel {
    func applyBackgroundRefreshUpdateIfNeeded(successToken: Int) async {
        guard successToken > 0 else {
            return
        }

        guard loadingState != .loading else {
            return
        }

        await reloadVisibleCachedPages()
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

    private func reloadVisibleCachedPages() async {
        let pagesToReload = visiblePageCount()
        var refreshedAlbums: [Album] = []
        var didReachEnd = false
        var loadedPageCount = 0

        do {
            for pageNumber in 1...pagesToReload {
                let pageAlbums = try await library.albums(page: LibraryPage(number: pageNumber, size: pageSize))
                loadedPageCount += 1
                refreshedAlbums.append(contentsOf: pageAlbums)
                if pageAlbums.count < pageSize {
                    didReachEnd = true
                    break
                }
            }

            albums = refreshedAlbums
            hasMorePages = !didReachEnd
            if didReachEnd {
                nextPageNumber = loadedPageCount == 1 ? 1 : loadedPageCount
            } else {
                nextPageNumber = loadedPageCount + 1
            }
            await refreshSearchResultsIfNeeded()
            loadingState = .loaded
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }

    private func visiblePageCount() -> Int {
        let loadedPages = hasMorePages ? max(nextPageNumber - 1, 1) : max(nextPageNumber, 1)
        return max(loadedPages, 1)
    }
}
