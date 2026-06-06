import Foundation
import Testing
@testable import Lunara

@MainActor
struct PlaybackURLResolverTests {
    @Test
    func resolve_returnsLocalFile_whenOfflineTrackExists() async throws {
        let offlineStore = MockOfflineStore()
        let library = ConfigurableLibraryRepoMock()
        let localURL = try #require(URL(string: "file:///offline/track-offline.flac"))
        offlineStore.localFileURLsByTrackID["track-offline"] = localURL

        let resolver = PlaybackURLResolver(offlineStore: offlineStore, library: library)
        let item = QueueItem(trackID: "track-offline", streamKey: "/library/metadata/track-offline")

        let resolved = try await resolver.resolvePlaybackURL(for: item, allowOffline: true)

        #expect(resolved == localURL)
        // Offline hit must not fall through to a stream-key lookup.
        #expect(library.streamURLForKeyRequests.isEmpty)
    }

    @Test
    func resolve_skipsOfflineFileAndStreams_whenAllowOfflineFalse() async throws {
        let offlineStore = MockOfflineStore()
        let library = ConfigurableLibraryRepoMock()
        // An offline copy DOES exist for this track...
        offlineStore.localFileURLsByTrackID["track-offline"] = try #require(URL(string: "file:///offline/track-offline.flac"))
        let streamURL = try #require(URL(string: "https://plex.example.com/library/metadata/track-offline?X-Plex-Token=abc"))
        library.streamURLToReturn = streamURL

        let resolver = PlaybackURLResolver(offlineStore: offlineStore, library: library)
        let item = QueueItem(trackID: "track-offline", streamKey: "/library/metadata/track-offline")

        // ...but allowOffline:false must bypass it and resolve a fresh stream URL,
        // so a recovery retry never re-picks the same bad offline file.
        let resolved = try await resolver.resolvePlaybackURL(for: item, allowOffline: false)

        #expect(resolved == streamURL)
        #expect(library.streamURLForKeyRequests == ["/library/metadata/track-offline"])
    }

    @Test
    func resolve_fallsBackToStreamFromKey_whenNoOfflineTrack() async throws {
        let offlineStore = MockOfflineStore()
        let library = ConfigurableLibraryRepoMock()
        let streamURL = try #require(URL(string: "https://plex.example.com/library/metadata/track-1?X-Plex-Token=abc"))
        library.streamURLToReturn = streamURL

        let resolver = PlaybackURLResolver(offlineStore: offlineStore, library: library)
        let item = QueueItem(trackID: "track-1", streamKey: "/library/metadata/track-1")

        let resolved = try await resolver.resolvePlaybackURL(for: item, allowOffline: true)

        #expect(resolved == streamURL)
        #expect(library.streamURLForKeyRequests == ["/library/metadata/track-1"])
    }

    @Test
    func resolve_usesStreamKey_whenNoOfflineStoreInjected() async throws {
        let library = ConfigurableLibraryRepoMock()
        let resolver = PlaybackURLResolver(offlineStore: nil, library: library)
        let item = QueueItem(trackID: "track-2", streamKey: "/library/metadata/track-2")

        _ = try await resolver.resolvePlaybackURL(for: item, allowOffline: true)

        #expect(library.streamURLForKeyRequests == ["/library/metadata/track-2"])
    }
}
