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
        client.artistIDByName["Sloan"] = "mb-sloan"
        client.upcomingByArtistID["mb-sloan"] = [
            ExternalReleaseGroup(id: "rg-new", title: "Future Album", firstReleaseYear: 2026, firstReleaseDate: "2026-09-04"),
            ExternalReleaseGroup(id: "rg-old", title: "Past Album", firstReleaseYear: 1998, firstReleaseDate: "1998-03-10")
        ]

        await service.refreshIfStale()

        #expect(service.entries.map(\.id) == ["rg-new"])
        #expect(store.savedRadarEntries.map(\.id) == ["rg-new"])
        #expect(client.upcomingIDRequests == ["mb-sloan"])
    }

    /// A refresh inside the 3-day window is skipped entirely.
    @Test
    func refreshIfStale_skipsWithinTheWindow() async throws {
        let (service, store, client, defaults) = makeSubject()
        store.ratedArtistNames = ["Sloan"]
        defaults.set(Date(timeIntervalSince1970: 1000), forKey: "radar.lastCheck")

        await service.refreshIfStale(now: Date(timeIntervalSince1970: 1000 + 24 * 3600))

        #expect(client.artistIDRequests.isEmpty)
        #expect(client.upcomingIDRequests.isEmpty)
    }

    // MARK: - Progress + incremental publish (Lunara-be2)

    /// Each artist's finds appear as soon as that artist is checked — not all
    /// at the end of a multi-minute sweep.
    @Test
    func refresh_publishesRowsAsArtistsComplete() async throws {
        let (service, store, client, _) = makeSubject()
        store.ratedArtistNames = ["Alpha", "Beta"]
        client.artistIDByName = ["Alpha": "mb-a", "Beta": "mb-b"]
        client.upcomingByArtistID["mb-a"] = [
            ExternalReleaseGroup(id: "rg-a", title: "A", firstReleaseYear: 2099, firstReleaseDate: "2099-01-01")
        ]
        client.upcomingByArtistID["mb-b"] = [
            ExternalReleaseGroup(id: "rg-b", title: "B", firstReleaseYear: 2099, firstReleaseDate: "2099-02-01")
        ]
        let snapshots = RadarSnapshotBox()
        client.onUpcomingByID = { artistID in
            await MainActor.run {
                snapshots.entryIDsByArtistID[artistID] = service.entries.map(\.id)
            }
        }

        await service.refreshIfStale()

        // By the time Beta's fetch starts, Alpha's find is already visible.
        #expect(snapshots.entryIDsByArtistID["mb-b"] == ["rg-a"])
        #expect(service.entries.map(\.id) == ["rg-a", "rg-b"])
    }

    @Test
    func refresh_tracksProgressCounters() async throws {
        let (service, store, client, _) = makeSubject()
        store.ratedArtistNames = ["Alpha", "Beta"]
        client.artistIDByName = ["Alpha": "mb-a", "Beta": "mb-b"]
        let snapshots = RadarSnapshotBox()
        client.onUpcomingByID = { artistID in
            await MainActor.run {
                snapshots.progressByArtistID[artistID] = RadarProgressSnapshot(
                    isRefreshing: service.isRefreshing,
                    checked: service.checkedCount,
                    total: service.totalArtists
                )
            }
        }

        await service.refreshIfStale()

        #expect(snapshots.progressByArtistID["mb-a"] == RadarProgressSnapshot(isRefreshing: true, checked: 0, total: 2))
        #expect(snapshots.progressByArtistID["mb-b"] == RadarProgressSnapshot(isRefreshing: true, checked: 1, total: 2))
        #expect(service.isRefreshing == false)
        #expect(service.checkedCount == 2)
    }

    /// Pull-to-refresh bypasses the 3-day gate.
    @Test
    func refreshForce_bypassesTheWindow() async throws {
        let (service, store, client, defaults) = makeSubject()
        store.ratedArtistNames = ["Sloan"]
        client.artistIDByName["Sloan"] = "mb-sloan"
        client.upcomingByArtistID["mb-sloan"] = [
            ExternalReleaseGroup(id: "rg-new", title: "Future", firstReleaseYear: 2099, firstReleaseDate: "2099-01-01")
        ]
        let now = Date(timeIntervalSince1970: 1000)
        defaults.set(now, forKey: "radar.lastCheck")

        await service.refresh(force: true, now: now)

        #expect(service.entries.map(\.id) == ["rg-new"])
        #expect(client.upcomingIDRequests == ["mb-sloan"])
    }

    // MARK: - MBID caching (Lunara-be2)

    @Test
    func refresh_usesCachedMBIDWithoutSearching() async throws {
        let (service, store, client, _) = makeSubject()
        store.ratedArtistNames = ["Sloan"]
        store.artistMBIDsByName["Sloan"] = "mb-sloan"
        client.upcomingByArtistID["mb-sloan"] = []

        await service.refreshIfStale()

        #expect(client.artistIDRequests.isEmpty)
        #expect(client.upcomingIDRequests == ["mb-sloan"])
    }

    @Test
    func refresh_persistsResolvedMBIDForTheNextSweep() async throws {
        let (service, store, client, _) = makeSubject()
        store.ratedArtistNames = ["Sloan"]
        client.artistIDByName["Sloan"] = "mb-sloan"

        await service.refreshIfStale()

        #expect(client.artistIDRequests == ["Sloan"])
        #expect(store.artistMBIDsByName["Sloan"] == "mb-sloan")
    }

    // MARK: - Empty-state signals (Lunara-be2)

    @Test
    func loadCached_flagsWhetherAnyArtistQualifies() async throws {
        let (noneQualify, _, _, _) = makeSubject()
        await noneQualify.loadCached()
        #expect(noneQualify.hasQualifyingArtists == false)

        let (someQualify, store, _, _) = makeSubject()
        store.ratedArtistNames = ["Sloan"]
        await someQualify.loadCached()
        #expect(someQualify.hasQualifyingArtists == true)
    }

    @Test
    func lastChecked_reflectsACompletedRefresh() async throws {
        let (service, store, client, _) = makeSubject()
        #expect(service.lastChecked == nil)
        store.ratedArtistNames = ["Sloan"]
        client.artistIDByName["Sloan"] = "mb-sloan"
        let now = Date(timeIntervalSince1970: 5000)

        await service.refreshIfStale(now: now)

        #expect(service.lastChecked == now)
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
    var artistMBIDsByName: [String: String] = [:]

    func artistNames(withAlbumRatedAtLeast rating: Int) async throws -> [String] {
        ratedArtistNames
    }

    func radarEntries() async throws -> [RadarEntry] {
        savedRadarEntries
    }

    func replaceRadarEntries(_ entries: [RadarEntry]) async throws {
        savedRadarEntries = entries
    }

    func artistMBID(name: String) async throws -> String? {
        artistMBIDsByName[name]
    }

    func saveArtistMBID(_ mbid: String, name: String) async throws {
        artistMBIDsByName[name] = mbid
    }
}

final class RadarMusicBrainzMock: MusicBrainzClientProtocol, @unchecked Sendable {
    var upcomingByArtistName: [String: [ExternalReleaseGroup]] = [:]
    private(set) var upcomingRequests: [String] = []
    var artistIDByName: [String: String] = [:]
    private(set) var artistIDRequests: [String] = []
    var upcomingByArtistID: [String: [ExternalReleaseGroup]] = [:]
    private(set) var upcomingIDRequests: [String] = []
    /// Awaited at the start of each by-ID fetch so tests can observe the
    /// service's published state mid-sweep.
    var onUpcomingByID: (@Sendable (String) async -> Void)?

    func artistEnrichment(name: String) async throws -> MusicBrainzArtistEnrichment? { nil }

    func upcomingAlbums(artistName: String) async throws -> [ExternalReleaseGroup] {
        upcomingRequests.append(artistName)
        return upcomingByArtistName[artistName] ?? []
    }

    func artistID(name: String) async throws -> String? {
        artistIDRequests.append(name)
        return artistIDByName[name]
    }

    func upcomingAlbums(artistID: String) async throws -> [ExternalReleaseGroup] {
        await onUpcomingByID?(artistID)
        upcomingIDRequests.append(artistID)
        return upcomingByArtistID[artistID] ?? []
    }
}

/// Mid-sweep observations captured from inside the MusicBrainz mock.
@MainActor
final class RadarSnapshotBox {
    var entryIDsByArtistID: [String: [String]] = [:]
    var progressByArtistID: [String: RadarProgressSnapshot] = [:]
}

struct RadarProgressSnapshot: Equatable {
    let isRefreshing: Bool
    let checked: Int
    let total: Int
}
