import Foundation
import Testing
@testable import Lunara

struct PlexArtworkURLBuilderTests {
    @Test func buildsTranscodeURLWithCap() throws {
        let builder = PlexArtworkURLBuilder(
            baseURL: URL(string: "https://example.plex.direct:32400")!,
            token: "token",
            maxSize: 2048
        )

        let url = builder.makeTranscodedArtworkURL(artPath: "/library/metadata/265/thumb/1715112705")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.path == "/photo/:/transcode")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(items["width"] == "2048")
        #expect(items["height"] == "2048")
        #expect(items["quality"] == "-1")
        #expect(items["url"]?.contains("/library/metadata/265/thumb/1715112705") == true)
    }
}
