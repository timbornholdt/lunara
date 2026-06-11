import Foundation

/// How the Release Radar orders its rows (Lunara-cl5). The service publishes
/// soonest-first; this sorts at the view layer so the sweep's
/// publish-as-you-go logic stays untouched.
enum RadarSort: String, CaseIterable, Identifiable {
    case releaseDate
    case artist

    var id: String { rawValue }

    private static let defaultsKey = "radar.sort"

    var label: String {
        switch self {
        case .releaseDate: return "Release Date"
        case .artist: return "Artist"
        }
    }

    func sorted(_ entries: [RadarEntry]) -> [RadarEntry] {
        switch self {
        case .releaseDate:
            return entries.sorted {
                ($0.firstReleaseDate, $0.title) < ($1.firstReleaseDate, $1.title)
            }
        case .artist:
            return entries.sorted {
                let comparison = $0.artistName.localizedCaseInsensitiveCompare($1.artistName)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return $0.firstReleaseDate < $1.firstReleaseDate
            }
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> RadarSort {
        defaults.string(forKey: Self.defaultsKey).flatMap(RadarSort.init(rawValue:)) ?? .releaseDate
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
