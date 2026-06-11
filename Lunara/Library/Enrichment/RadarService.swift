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
    func artistMBID(name: String) async throws -> String?
    func saveArtistMBID(_ mbid: String, name: String) async throws
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

    // Sweep progress (Lunara-be2): the view shows "Checking your artists… x/y"
    // while a multi-minute throttled sweep runs.
    private(set) var isRefreshing = false
    private(set) var checkedCount = 0
    private(set) var totalArtists = 0
    /// Defaults true so the "rate some albums" empty state never flashes
    /// before the store has answered.
    private(set) var hasQualifyingArtists = true

    var lastChecked: Date? {
        defaults.object(forKey: Self.lastCheckKey) as? Date
    }

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

    /// Publishes the persisted radar without touching the network, and answers
    /// whether anyone qualifies so the view can pick the right empty state.
    func loadCached() async {
        entries = (try? await store.radarEntries()) ?? []
        if let artists = try? await store.artistNames(withAlbumRatedAtLeast: Self.minimumRating) {
            hasQualifyingArtists = !artists.isEmpty
        }
    }

    /// Refreshes from MusicBrainz when the last check is older than the window.
    /// One throttled artist lookup chain per rated artist, run while the app is
    /// open — a ~50-artist library takes ~1 minute of quiet background fetching
    /// once MBIDs are cached (~2 minutes on the first sweep).
    func refreshIfStale(now: Date = Date()) async {
        await refresh(force: false, now: now)
    }

    /// Full sweep; `force` bypasses the 3-day gate (pull-to-refresh). Results
    /// publish as each artist completes, never all at the end (Lunara-be2).
    func refresh(force: Bool = false, now: Date = Date()) async {
        guard !isRefreshing else { return }
        if !force,
           let last = lastChecked,
           now.timeIntervalSince(last) < Self.refreshInterval {
            return
        }

        guard let artists = try? await store.artistNames(withAlbumRatedAtLeast: Self.minimumRating) else {
            return
        }
        hasQualifyingArtists = !artists.isEmpty
        guard !artists.isEmpty else { return }

        isRefreshing = true
        totalArtists = artists.count
        checkedCount = 0
        defer { isRefreshing = false }

        let today = Self.dateString(from: now)
        var fresh: [RadarEntry] = []
        // Cached rows are swapped out per artist as fresh results land, so the
        // visible list never blanks mid-sweep.
        var carryover = entries
        for artist in artists {
            if let albums = try? await upcomingAlbums(for: artist) {
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
            checkedCount += 1
            carryover.removeAll { $0.artistName == artist }
            entries = (fresh + carryover).sorted(by: Self.soonestFirst)
        }

        fresh.sort(by: Self.soonestFirst)
        try? await store.replaceRadarEntries(fresh)
        entries = fresh
        defaults.set(now, forKey: Self.lastCheckKey)
        logger.info("Radar refreshed: \(fresh.count, privacy: .public) upcoming albums across \(artists.count, privacy: .public) rated artists")
    }

    /// Resolves the artist's MBID (cache first, search once and persist) and
    /// fetches their release groups — one request per artist after the first
    /// sweep instead of two. Logs cache HIT/MISS + elapsed per artist so sweep
    /// speed claims are verifiable on device (Lunara-g0p).
    private func upcomingAlbums(for artist: String) async throws -> [ExternalReleaseGroup] {
        let start = ContinuousClock.now
        var mbid = try? await store.artistMBID(name: artist)
        let cacheHit = mbid != nil
        if mbid == nil {
            mbid = try await musicBrainz.artistID(name: artist)
            if let mbid {
                try? await store.saveArtistMBID(mbid, name: artist)
            }
        }
        guard let mbid else {
            logger.info("radar sweep: '\(artist, privacy: .public)' no confident MBID match (\(Self.ms(since: start), privacy: .public)ms)")
            return []
        }
        let albums = try await musicBrainz.upcomingAlbums(artistID: mbid)
        logger.info("radar sweep: '\(artist, privacy: .public)' mbid \(cacheHit ? "HIT" : "MISS", privacy: .public) \(albums.count, privacy: .public) groups in \(Self.ms(since: start), privacy: .public)ms")
        return albums
    }

    private static func ms(since start: ContinuousClock.Instant) -> Int {
        let elapsed = start.duration(to: .now)
        return Int(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
    }

    private static func soonestFirst(_ lhs: RadarEntry, _ rhs: RadarEntry) -> Bool {
        (lhs.firstReleaseDate, lhs.title) < (rhs.firstReleaseDate, rhs.title)
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
