import Foundation

enum LibraryRefreshReason: Equatable, Sendable {
    case appLaunch
    case userInitiated
}

struct LibraryRefreshOutcome: Equatable, Sendable {
    let reason: LibraryRefreshReason
    let refreshedAt: Date
    let albumCount: Int
    let trackCount: Int
    let artistCount: Int
    let collectionCount: Int

    var totalItemCount: Int {
        albumCount + trackCount + artistCount + collectionCount
    }
}

@MainActor
protocol LibraryRepoProtocol: AnyObject {
    /// Reads a single cached album page.
    /// Implementations should return quickly from local storage.
    func albums(page: LibraryPage) async throws -> [Album]
    func album(id: String) async throws -> Album?

    func tracks(forAlbum albumID: String) async throws -> [Track]
    func collections() async throws -> [Collection]
    func artists() async throws -> [Artist]
    func artist(id: String) async throws -> Artist?

    /// Performs a remote refresh and persists it atomically.
    /// Implementations must preserve existing cache when this throws.
    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome
    func lastRefreshDate() async throws -> Date?

    func streamURL(for track: Track) async throws -> URL
    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL?
}

extension LibraryRepoProtocol {
    /// Convenience helper for callers that still need a full in-memory list.
    /// Fetches paginated data and preserves thrown errors from any page read.
    func fetchAlbums(pageSize: Int = 200) async throws -> [Album] {
        var allAlbums: [Album] = []
        var pageNumber = 1
        let sanitizedPageSize = max(1, pageSize)

        while true {
            let page = LibraryPage(number: pageNumber, size: sanitizedPageSize)
            let batch = try await albums(page: page)
            allAlbums.append(contentsOf: batch)

            if batch.count < sanitizedPageSize {
                break
            }

            pageNumber += 1
        }

        return allAlbums
    }

    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? {
        guard let rawValue,
              let sourceURL = URL(string: rawValue),
              sourceURL.scheme != nil else {
            return nil
        }

        return sourceURL
    }
}

extension PlexAPIClient: LibraryRepoProtocol {
    func albums(page: LibraryPage) async throws -> [Album] {
        let allAlbums = try await fetchAlbums()
        guard page.offset < allAlbums.count else {
            return []
        }

        let endIndex = min(page.offset + page.size, allAlbums.count)
        return Array(allAlbums[page.offset..<endIndex])
    }

    func album(id: String) async throws -> Album? {
        let allAlbums = try await fetchAlbums()
        return allAlbums.first { $0.plexID == id }
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        try await fetchTracks(forAlbum: albumID)
    }

    func collections() async throws -> [Collection] {
        throw LibraryError.operationFailed(reason: "Collections fetch is not implemented on PlexAPIClient-backed LibraryRepo yet.")
    }

    func artists() async throws -> [Artist] {
        throw LibraryError.operationFailed(reason: "Artists fetch is not implemented on PlexAPIClient-backed LibraryRepo yet.")
    }

    func artist(id: String) async throws -> Artist? {
        throw LibraryError.operationFailed(reason: "Artist fetch is not implemented on PlexAPIClient-backed LibraryRepo yet.")
    }

    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        throw LibraryError.operationFailed(reason: "Library refresh orchestration is not implemented yet.")
    }

    func lastRefreshDate() async throws -> Date? {
        nil
    }

    func streamURL(for track: Track) async throws -> URL {
        try await streamURL(forTrack: track)
    }

}
