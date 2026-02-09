import Foundation

struct UserDefaultsServerAddressStore: PlexServerAddressStoring {
    private let defaults: UserDefaults
    private let key = "plex.server.baseURL"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var serverURL: URL? {
        get {
            guard let value = defaults.string(forKey: key) else { return nil }
            return URL(string: value)
        }
        set {
            defaults.set(newValue?.absoluteString, forKey: key)
        }
    }
}

struct UserDefaultsLibrarySelectionStore: PlexLibrarySelectionStoring {
    private let defaults: UserDefaults
    private let key = "plex.library.selectedSectionKey"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedSectionKey: String? {
        get { defaults.string(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
