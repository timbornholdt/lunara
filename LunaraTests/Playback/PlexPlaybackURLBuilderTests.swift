import Foundation
import Testing
@testable import Lunara

struct PlexPlaybackURLBuilderTests {
    @Test func buildsDirectPlayURLWithTokenAndClientInfo() throws {
        let builder = PlexPlaybackURLBuilder(
            baseURL: URL(string: "https://example.com:32400")!,
            token: "token",
            configuration: PlexClientConfiguration(
                clientIdentifier: "client-1",
                product: "Lunara",
                version: "1.0",
                platform: "iOS"
            )
        )

        let url = builder.makeDirectPlayURL(partKey: "/library/parts/123/file.flac")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItemsDictionary

        #expect(components.path == "/library/parts/123/file.flac")
        #expect(items["X-Plex-Token"] == "token")
        #expect(items["X-Plex-Client-Identifier"] == "client-1")
        #expect(items["X-Plex-Product"] == "Lunara")
        #expect(items["X-Plex-Version"] == "1.0")
        #expect(items["X-Plex-Platform"] == "iOS")
    }

    @Test func buildsTranscodeURLWithExpectedQueryItems() throws {
        let builder = PlexPlaybackURLBuilder(
            baseURL: URL(string: "https://example.com:32400")!,
            token: "token",
            configuration: PlexClientConfiguration(
                clientIdentifier: "client-1",
                product: "Lunara",
                version: "1.0",
                platform: "iOS"
            )
        )

        let url = try #require(builder.makeTranscodeURL(trackRatingKey: "42"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItemsDictionary

        #expect(components.path == "/music/:/transcode/universal/start.m3u8")
        #expect(items["path"] == "/library/metadata/42")
        #expect(items["protocol"] == "hls")
        #expect(items["mediaIndex"] == "0")
        #expect(items["partIndex"] == "0")
        #expect(items["musicBitrate"] == "128")
        #expect(items["audioCodec"] == "mp3")
        #expect(items["X-Plex-Token"] == "token")
        #expect(items["X-Plex-Client-Identifier"] == "client-1")
        #expect(items["X-Plex-Product"] == "Lunara")
        #expect(items["X-Plex-Version"] == "1.0")
        #expect(items["X-Plex-Platform"] == "iOS")
    }
}

private extension URLComponents {
    var queryItemsDictionary: [String: String] {
        Dictionary(uniqueKeysWithValues: (queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}
