import Foundation
import Testing
@testable import Lunara

struct PlaybackSourceResolverTests {
    @Test func prefersLocalFileWhenAvailable() throws {
        let localIndex = StubLocalPlaybackIndex(fileURL: URL(fileURLWithPath: "/tmp/track.mp3"))
        let builder = PlexPlaybackURLBuilder(
            baseURL: URL(string: "https://example.com:32400")!,
            token: "token",
            configuration: PlexClientConfiguration(clientIdentifier: "client", product: "Lunara", version: "1", platform: "iOS")
        )
        let resolver = PlaybackSourceResolver(localIndex: localIndex, urlBuilder: builder)
        let track = PlexTrack(
            ratingKey: "1",
            title: "Track",
            index: 1,
            parentIndex: nil,
            parentRatingKey: "10",
            duration: 1000,
            media: [PlexTrackMedia(parts: [PlexTrackPart(key: "/library/parts/123/file.mp3")])]
        )

        let source = resolver.resolveSource(for: track)

        #expect(source == .local(fileURL: URL(fileURLWithPath: "/tmp/track.mp3")))
    }

    @Test func fallsBackToRemoteWhenNoLocalFile() throws {
        let builder = PlexPlaybackURLBuilder(
            baseURL: URL(string: "https://example.com:32400")!,
            token: "token",
            configuration: PlexClientConfiguration(clientIdentifier: "client", product: "Lunara", version: "1", platform: "iOS")
        )
        let resolver = PlaybackSourceResolver(localIndex: nil, urlBuilder: builder)
        let track = PlexTrack(
            ratingKey: "1",
            title: "Track",
            index: 1,
            parentIndex: nil,
            parentRatingKey: "10",
            duration: 1000,
            media: [PlexTrackMedia(parts: [PlexTrackPart(key: "/library/parts/123/file.mp3")])]
        )

        let source = resolver.resolveSource(for: track)

        let expectedURL = builder.makeDirectPlayURL(partKey: "/library/parts/123/file.mp3")
        #expect(source == .remote(url: expectedURL))
    }

    @Test func returnsNilWhenNetworkUnavailableAndNoLocalFile() throws {
        let builder = PlexPlaybackURLBuilder(
            baseURL: URL(string: "https://example.com:32400")!,
            token: "token",
            configuration: PlexClientConfiguration(clientIdentifier: "client", product: "Lunara", version: "1", platform: "iOS")
        )
        let resolver = PlaybackSourceResolver(
            localIndex: nil,
            urlBuilder: builder,
            networkMonitor: StubNetworkReachabilityMonitor(isReachable: false)
        )
        let track = PlexTrack(
            ratingKey: "1",
            title: "Track",
            index: 1,
            parentIndex: nil,
            parentRatingKey: "10",
            duration: 1000,
            media: [PlexTrackMedia(parts: [PlexTrackPart(key: "/library/parts/123/file.mp3")])]
        )

        let source = resolver.resolveSource(for: track)

        #expect(source == nil)
    }
}

private struct StubLocalPlaybackIndex: LocalPlaybackIndexing {
    let fileURL: URL?

    func fileURL(for trackKey: String) -> URL? {
        fileURL
    }

    func markPlayed(trackKey: String, at date: Date) {
    }
}

private struct StubNetworkReachabilityMonitor: NetworkReachabilityMonitoring {
    let isReachable: Bool
}
