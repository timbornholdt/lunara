import Foundation
import Observation
import os

/// One upcoming album on the release radar (Lunara-nlo).
struct RadarEntry: Equatable, Sendable, Identifiable {
    /// MusicBrainz release-group ID.
    let id: String
    let artistName: String
    let title: String
    /// Raw MusicBrainz date: "yyyy", "yyyy-MM", or "yyyy-MM-dd".
    let firstReleaseDate: String

    var musicBrainzURL: URL {
        URL(string: "https://musicbrainz.org/release-group/\(id)")!
    }
}

/// The slice of the library store the radar needs: which artists earned a spot
/// (any album rated 4.5★+) and the persisted radar entries.
@MainActor
protocol RadarStoring: AnyObject {
    func artistNames(withAlbumRatedAtLeast rating: Int) async throws -> [String]
    func radarEntries() async throws -> [RadarEntry]
    func replaceRadarEntries(_ entries: [RadarEntry]) async throws
}

extension LibraryStore: RadarStoring { }

/// Release radar: upcoming albums from artists with a 4.5★+ album, sourced from
/// MusicBrainz (the keyless Apple endpoints carry no pre-release catalog —
/// verified empirically, see Lunara-nlo). Refreshes opportunistically on launch
/// at most every `refreshInterval`; entries persist so the view is instant and
/// offline. No background tasks, no polling (battery).
@MainActor
@Observable
final class RadarService {
    private(set) var entries: [RadarEntry] = []

    /// Plex ratings are 0–10; 9 = 4.5 stars.
    static let minimumRating = 9
    static let refreshInterval: TimeInterval = 3 * 24 * 3600
    private static let lastCheckKey = "radar.lastCheck"

    private let store: RadarStoring
    private let musicBrainz: MusicBrainzClientProtocol
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "RadarService")

    init(
        store: RadarStoring,
        musicBrainz: MusicBrainzClientProtocol,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.musicBrainz = musicBrainz
        self.defaults = defaults
    }

    /// Publishes the persisted radar without touching the network.
    func loadCached() async {
        entries = (try? await store.radarEntries()) ?? []
    }

    /// Refreshes from MusicBrainz when the last check is older than the window.
    /// One throttled artist lookup chain per rated artist, run while the app is
    /// open — a ~50-artist library takes ~2 minutes of quiet background fetching.
    func refreshIfStale(now: Date = Date()) async {
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           now.timeIntervalSince(last) < Self.refreshInterval {
            return
        }

        guard let artists = try? await store.artistNames(withAlbumRatedAtLeast: Self.minimumRating),
              !artists.isEmpty else {
            return
        }

        let today = Self.dateString(from: now)
        var fresh: [RadarEntry] = []
        for artist in artists {
            guard let albums = try? await musicBrainz.upcomingAlbums(artistName: artist) else { continue }
            for album in albums {
                guard let date = album.firstReleaseDate, Self.isUpcoming(date, today: today) else { continue }
                fresh.append(RadarEntry(
                    id: album.id,
                    artistName: artist,
                    title: album.title,
                    firstReleaseDate: date
                ))
            }
        }

        fresh.sort { $0.firstReleaseDate < $1.firstReleaseDate }
        try? await store.replaceRadarEntries(fresh)
        entries = fresh
        defaults.set(now, forKey: Self.lastCheckKey)
        logger.info("Radar refreshed: \(fresh.count, privacy: .public) upcoming albums across \(artists.count, privacy: .public) rated artists")
    }

    /// Whether a MusicBrainz date counts as upcoming, compared at the date's own
    /// granularity — "2026-06" or "2026" match anything in that month/year, so
    /// partial dates err inclusive rather than vanishing from the radar.
    static func isUpcoming(_ date: String, today: String) -> Bool {
        guard !date.isEmpty else { return false }
        return date >= String(today.prefix(date.count))
    }

    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
