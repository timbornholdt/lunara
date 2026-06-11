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

/// Same pattern for MusicBrainz enrichment (Lunara-uww.6.2 / 6.3).
private struct MusicBrainzClientKey: EnvironmentKey {
    static let defaultValue: MusicBrainzClientProtocol? = nil
}

extension EnvironmentValues {
    var musicBrainzClient: MusicBrainzClientProtocol? {
        get { self[MusicBrainzClientKey.self] }
        set { self[MusicBrainzClientKey.self] = newValue }
    }
}
