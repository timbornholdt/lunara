import Foundation
import Testing
@testable import Lunara

struct AlbumDuplicateDebugReporterTests {
    @Test
    func makeReport_withExactDuplicates_includesExactGroupAndEntries() {
        let reporter = AlbumDuplicateDebugReporter()
        let albums = [
            makeAlbum(id: "a2", title: "After the Gold Rush", artist: "Neil Young", year: 1970),
            makeAlbum(id: "a1", title: "After the Gold Rush", artist: "Neil Young", year: 1970),
            makeAlbum(id: "b1", title: "Harvest", artist: "Neil Young", year: 1972)
        ]

        let report = reporter.makeReport(albums: albums)

        #expect(report.contains("Exact duplicate groups (artist + title + year): 1"))
        #expect(report.contains("[1] Neil Young - After the Gold Rush (2 entries)"))
        #expect(report.contains("id=a1"))
        #expect(report.contains("id=a2"))
    }

    @Test
    func makeReport_withTitleArtistYearMismatch_reportsCandidateDuplicateGroup() {
        let reporter = AlbumDuplicateDebugReporter()
        let albums = [
            makeAlbum(id: "a1", title: "After the Gold Rush", artist: "Neil Young", year: 1970),
            makeAlbum(id: "a2", title: "After the Gold Rush", artist: "Neil Young", year: nil)
        ]

        let report = reporter.makeReport(albums: albums)

        #expect(report.contains("Exact duplicate groups (artist + title + year): 0"))
        #expect(report.contains("Candidate duplicate groups (artist + title, year ignored): 1"))
    }

    @Test
    func makeReport_withSpotlightFilter_listsMatchingAlbums() {
        let reporter = AlbumDuplicateDebugReporter()
        let albums = [
            makeAlbum(id: "a1", title: "After the Gold Rush", artist: "Neil Young", year: 1970),
            makeAlbum(id: "b1", title: "Harvest", artist: "Neil Young", year: 1972)
        ]

        let report = reporter.makeReport(
            albums: albums,
            spotlightTitle: "After the Gold Rush",
            spotlightArtist: "Neil Young"
        )

        #expect(report.contains("Spotlight matches:"))
        #expect(report.contains("id=a1"))
        #expect(!report.contains("id=b1"))
    }

    private func makeAlbum(id: String, title: String, artist: String, year: Int?) -> Album {
        Album(
            plexID: id,
            title: title,
            artistName: artist,
            year: year,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 1,
            duration: 100
        )
    }
}
