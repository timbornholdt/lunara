import Foundation
import Testing
@testable import Lunara

/// Lunara-cl5: radar rows sort by release date (default) or by artist.
struct RadarSortTests {
    private let entries = [
        RadarEntry(id: "rg-1", artistName: "Sloan", title: "Later", firstReleaseDate: "2026-10-01"),
        RadarEntry(id: "rg-2", artistName: "cheekface", title: "Sooner", firstReleaseDate: "2026-07-01"),
        RadarEntry(id: "rg-3", artistName: "Cheekface", title: "Soonest", firstReleaseDate: "2026-06-20"),
        RadarEntry(id: "rg-4", artistName: "Sloan", title: "First Overall", firstReleaseDate: "2026-06-01")
    ]

    @Test
    func releaseDateSort_isSoonestFirst() {
        let sorted = RadarSort.releaseDate.sorted(entries)
        #expect(sorted.map(\.id) == ["rg-4", "rg-3", "rg-2", "rg-1"])
    }

    @Test
    func artistSort_groupsCaseInsensitivelyThenSoonestFirst() {
        let sorted = RadarSort.artist.sorted(entries)
        // Cheekface (either casing) before Sloan; within an artist, soonest first.
        #expect(sorted.map(\.id) == ["rg-3", "rg-2", "rg-4", "rg-1"])
    }

    @Test
    func persistsAndRestoresFromDefaults() {
        let defaults = UserDefaults(suiteName: "radar-sort-\(UUID().uuidString)")!
        #expect(RadarSort.load(from: defaults) == .releaseDate)

        RadarSort.artist.save(to: defaults)
        #expect(RadarSort.load(from: defaults) == .artist)
    }
}
