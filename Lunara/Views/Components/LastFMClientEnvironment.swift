import SwiftUI

/// Injects the shared Last.fm client for read-only enrichment (artist bios,
/// Lunara-uww.6.1) without threading it through every view-model factory.
/// nil in previews/tests that don't provide one — consumers must treat it
/// as optional and skip enrichment.
private struct LastFMClientKey: EnvironmentKey {
    static let defaultValue: LastFMClientProtocol? = nil
}

extension EnvironmentValues {
    var lastFMClient: LastFMClientProtocol? {
        get { self[LastFMClientKey.self] }
        set { self[LastFMClientKey.self] = newValue }
    }
}
