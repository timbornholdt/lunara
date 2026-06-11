import Foundation
import Testing
@testable import Lunara

/// Lunara-mam: Albums grid sorts — artist (store order), release date, random.
struct AlbumGridSortTests {
    private let albums = [
        makeAlbum(id: "al-1", title: "Zen Arcade", artist: "Hüsker Dü", releaseDate: date("1984-07-01")),
        makeAlbum(id: "al-2", title: "Smeared", artist: "sloan", releaseDate: date("1992-08-01")),
        makeAlbum(id: "al-3", title: "One Chord to Another", artist: "Sloan", releaseDate: date("1996-06-07")),
        makeAlbum(id: "al-4", title: "Mystery", artist: "Apples", releaseDate: nil, year: nil),
        makeAlbum(id: "al-5", title: "Year Only", artist: "Apples", releaseDate: nil, year: 2001)
    ]

    @Test
    func artistSort_groupsArtistsCaseInsensitivelyThenByTitle() {
        let sorted = AlbumGridSort.artist.sorted(albums, randomSeed: 0)
        // Apples (Mystery < Year Only), Hüsker Dü, then sloan/Sloan as one
        // artist with titles ordered: One Chord… < Smeared.
        #expect(sorted.map(\.plexID) == ["al-4", "al-5", "al-1", "al-3", "al-2"])
    }

    @Test
    func releaseDateSort_newestFirstWithYearFallbackAndUnknownLast() {
        let sorted = AlbumGridSort.releaseDate.sorted(albums, randomSeed: 0)
        // 1996 > 1992 > 1984; year-only 2001 resolves to that year; unknown last.
        #expect(sorted.map(\.plexID) == ["al-5", "al-3", "al-2", "al-1", "al-4"])
    }

    @Test
    func randomSort_isDeterministicPerSeedAndReshufflesAcrossSeeds() {
        let first = AlbumGridSort.random.sorted(albums, randomSeed: 42)
        let again = AlbumGridSort.random.sorted(albums, randomSeed: 42)
        #expect(first.map(\.plexID) == again.map(\.plexID))
        #expect(Set(first.map(\.plexID)) == Set(albums.map(\.plexID)))

        // Some seed must produce a different order (5! permutations; check a few).
        let otherOrders = (1...5).map { AlbumGridSort.random.sorted(albums, randomSeed: UInt64($0)).map(\.plexID) }
        #expect(otherOrders.contains { $0 != first.map(\.plexID) })
    }

    @Test
    func persistsAndRestoresFromDefaults() {
        let defaults = UserDefaults(suiteName: "albums-sort-\(UUID().uuidString)")!
        #expect(AlbumGridSort.load(from: defaults) == .artist)

        AlbumGridSort.releaseDate.save(to: defaults)
        #expect(AlbumGridSort.load(from: defaults) == .releaseDate)
    }

    private static func makeAlbum(id: String, title: String, artist: String, releaseDate: Date?, year: Int? = nil) -> Album {
        Album(
            plexID: id, title: title, artistName: artist, year: year,
            releaseDate: releaseDate, thumbURL: nil, genre: nil, rating: nil,
            addedAt: nil, trackCount: 10, duration: 1800
        )
    }

    private static func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)!
    }
}
