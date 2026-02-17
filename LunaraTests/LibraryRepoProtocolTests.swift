import Foundation
import Testing
@testable import Lunara

@MainActor
struct LibraryRepoProtocolTests {
    @Test
    func libraryRefreshOutcome_totalItemCount_sumsAllEntityCounts() {
        let outcome = LibraryRefreshOutcome(
            reason: .userInitiated,
            refreshedAt: Date(timeIntervalSince1970: 1_705_000_000),
            albumCount: 12,
            trackCount: 121,
            artistCount: 6,
            collectionCount: 3
        )

        #expect(outcome.totalItemCount == 142)
    }

    @Test
    func fetchAlbums_readsSequentialPagesUntilShortPageReturned() async throws {
        let repo = ProtocolRepoMock()
        repo.albumsByPage[1] = [makeAlbum(id: "album-1"), makeAlbum(id: "album-2")]
        repo.albumsByPage[2] = [makeAlbum(id: "album-3")]

        let albums = try await repo.fetchAlbums(pageSize: 2)

        #expect(repo.albumPageRequests == [
            LibraryPage(number: 1, size: 2),
            LibraryPage(number: 2, size: 2)
        ])
        #expect(albums.map(\.plexID) == ["album-1", "album-2", "album-3"])
    }

    @Test
    func fetchAlbums_whenPagedReadFails_propagatesOriginalError() async {
        let repo = ProtocolRepoMock()
        repo.albumsByPage[1] = [makeAlbum(id: "album-1")]
        repo.albumsErrorByPage[2] = .databaseCorrupted

        do {
            _ = try await repo.fetchAlbums(pageSize: 1)
            Issue.record("Expected fetchAlbums to throw")
        } catch let error as LibraryError {
            #expect(error == .databaseCorrupted)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }

        #expect(repo.albumPageRequests == [
            LibraryPage(number: 1, size: 1),
            LibraryPage(number: 2, size: 1)
        ])
    }

    private func makeAlbum(id: String) -> Album {
        Album(
            plexID: id,
            title: "Album \(id)",
            artistName: "Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 0,
            duration: 0
        )
    }
}

@MainActor
private final class ProtocolRepoMock: LibraryRepoProtocol {
    var albumsByPage: [Int: [Album]] = [:]
    var albumsErrorByPage: [Int: LibraryError] = [:]
    var albumPageRequests: [LibraryPage] = []

    func albums(page: LibraryPage) async throws -> [Album] {
        albumPageRequests.append(page)
        if let error = albumsErrorByPage[page.number] {
            throw error
        }
        return albumsByPage[page.number] ?? []
    }

    func album(id: String) async throws -> Album? {
        nil
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        []
    }

    func collections() async throws -> [Collection] {
        []
    }

    func artists() async throws -> [Artist] {
        []
    }

    func artist(id: String) async throws -> Artist? {
        nil
    }

    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        LibraryRefreshOutcome(
            reason: reason,
            refreshedAt: Date(timeIntervalSince1970: 0),
            albumCount: 0,
            trackCount: 0,
            artistCount: 0,
            collectionCount: 0
        )
    }

    func lastRefreshDate() async throws -> Date? {
        nil
    }

    func streamURL(for track: Track) async throws -> URL {
        throw LibraryError.resourceNotFound(type: "track", id: track.plexID)
    }
}
