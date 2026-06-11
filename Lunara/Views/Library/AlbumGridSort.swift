import Foundation

/// How the Albums grid orders the full catalog (Lunara-mam). Sorting happens
/// in memory over the loaded-all catalog; `random` is deterministic per seed
/// so a session's order is stable until the user reshuffles.
enum AlbumGridSort: String, CaseIterable, Identifiable {
    case artist
    case releaseDate
    case random

    var id: String { rawValue }

    private static let defaultsKey = "albums.sort"

    var label: String {
        switch self {
        case .artist: return "Artist"
        case .releaseDate: return "Release Date"
        case .random: return "Random"
        }
    }

    func sorted(_ albums: [Album], randomSeed: UInt64) -> [Album] {
        switch self {
        case .artist:
            return albums.sorted { lhs, rhs in
                let artists = lhs.artistName.localizedCaseInsensitiveCompare(rhs.artistName)
                if artists != .orderedSame { return artists == .orderedAscending }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        case .releaseDate:
            return albums.sorted { lhs, rhs in
                Self.releaseSortDate(lhs) > Self.releaseSortDate(rhs)
            }
        case .random:
            var generator = SplitMix64(seed: randomSeed)
            return albums.shuffled(using: &generator)
        }
    }

    /// Newest first; a year-only album counts as that year; unknown sinks last.
    private static func releaseSortDate(_ album: Album) -> Date {
        if let releaseDate = album.releaseDate { return releaseDate }
        if let year = album.year {
            var components = DateComponents()
            components.year = year
            components.timeZone = TimeZone(identifier: "UTC")
            if let date = Calendar(identifier: .gregorian).date(from: components) {
                return date
            }
        }
        return .distantPast
    }

    static func load(from defaults: UserDefaults = .standard) -> AlbumGridSort {
        defaults.string(forKey: Self.defaultsKey).flatMap(AlbumGridSort.init(rawValue:)) ?? .artist
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// Tiny deterministic RNG for the seeded shuffle — SplitMix64.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
