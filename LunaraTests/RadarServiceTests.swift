import Foundation
import Testing
@testable import Lunara

/// Lunara-nlo: release radar — upcoming albums from 4.5★+ artists.
@MainActor
struct RadarServiceTests {
    @Test
    func isUpcoming_comparesAtTheDateOwnGranularity() {
        let today = "2026-06-11"
        #expect(RadarService.isUpcoming("2026-06-12", today: today))
        #expect(!RadarService.isUpcoming("2026-06-10", today: today))
        // Month granularity: this month counts as upcoming.
        #expect(RadarService.isUpcoming("2026-06", today: today))
        #expect(!RadarService.isUpcoming("2026-05", today: today))
        // Year granularity: this year counts as upcoming (errs inclusive).
        #expect(RadarService.isUpcoming("2026", today: today))
        #expect(!RadarService.isUpcoming("2025", today: today))
        #expect(!RadarService.isUpcoming("", today: today))
    }

    @Test
    func refreshIfStale_fetchesPersistsAndPublishesUpcomingAlbums() async throws {
        let (service, store, client, _) = makeSubject()
        store.ratedArtistNames = ["Sloan"]
        client.upcomingByArtistName["Sloan"] = [
            ExternalReleaseGroup(id: "rg-new", title: "Future Album", firstReleaseYear: 2026, firstReleaseDate: "2026-09-04"),
            ExternalReleaseGroup(id: "rg-old", title: "Past Album", firstReleaseYear: 1998, firstReleaseDate: "1998-03-10")
        ]

        await service.refreshIfStale()

        #expect(service.entries.map(\.id) == ["rg-new"])
        #expect(store.savedRadarEntries.map(\.id) == ["rg-new"])
        #expect(client.upcomingRequests == ["Sloan"])
    }

    /// A refresh inside the 3-day window is skipped entirely.
    @Test
    func refreshIfStale_skipsWithinTheWindow() async throws {
        let (service, store, client, defaults) = makeSubject()
        store.ratedArtistNames = ["Sloan"]
        defaults.set(Date(timeIntervalSince1970: 1000), forKey: "radar.lastCheck")

        await service.refreshIfStale(now: Date(timeIntervalSince1970: 1000 + 24 * 3600))

        #expect(client.upcomingRequests.isEmpty)
    }

    @Test
    func loadCached_publishesPersistedEntriesWithoutNetwork() async throws {
        let (service, store, client, _) = makeSubject()
        store.savedRadarEntries = [
            RadarEntry(id: "rg-1", artistName: "Sloan", title: "Cached", firstReleaseDate: "2026-08-01")
        ]

        await service.loadCached()

        #expect(service.entries.map(\.id) == ["rg-1"])
        #expect(client.upcomingRequests.isEmpty)
    }

    private func makeSubject() -> (RadarService, RadarStoreMock, RadarMusicBrainzMock, UserDefaults) {
        let store = RadarStoreMock()
        let client = RadarMusicBrainzMock()
        let defaults = UserDefaults(suiteName: "radar-test-\(UUID().uuidString)")!
        let service = RadarService(
            store: store,
            musicBrainz: client,
            defaults: defaults
        )
        return (service, store, client, defaults)
    }
}

// MARK: - Doubles

@MainActor
final class RadarStoreMock: RadarStoring {
    var ratedArtistNames: [String] = []
    var savedRadarEntries: [RadarEntry] = []

    func artistNames(withAlbumRatedAtLeast rating: Int) async throws -> [String] {
        ratedArtistNames
    }

    func radarEntries() async throws -> [RadarEntry] {
        savedRadarEntries
    }

    func replaceRadarEntries(_ entries: [RadarEntry]) async throws {
        savedRadarEntries = entries
    }
}

final class RadarMusicBrainzMock: MusicBrainzClientProtocol, @unchecked Sendable {
    var upcomingByArtistName: [String: [ExternalReleaseGroup]] = [:]
    private(set) var upcomingRequests: [String] = []

    func artistEnrichment(name: String) async throws -> MusicBrainzArtistEnrichment? { nil }

    func upcomingAlbums(artistName: String) async throws -> [ExternalReleaseGroup] {
        upcomingRequests.append(artistName)
        return upcomingByArtistName[artistName] ?? []
    }
}
