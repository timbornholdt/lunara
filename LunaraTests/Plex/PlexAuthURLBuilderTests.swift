import Foundation
import Testing
@testable import Lunara

struct PlexAuthURLBuilderTests {
    @Test func buildsAuthURLWithFragmentQuery() throws {
        let builder = PlexAuthURLBuilder()
        let url = builder.makeAuthURL(
            code: "abcd",
            clientIdentifier: "client-id",
            product: "Lunara",
            forwardURL: URL(string: "https://app.plex.tv/desktop/")
        )

        let result = try #require(url)
        let components = try #require(URLComponents(url: result, resolvingAgainstBaseURL: false))
        #expect(components.host == "app.plex.tv")
        #expect(components.path == "/auth")
        let fragment = try #require(components.fragment)
        #expect(fragment.hasPrefix("?"))
        #expect(fragment.contains("clientID=client-id"))
        #expect(fragment.contains("code=abcd"))
        #expect(fragment.contains("context%5Bdevice%5D%5Bproduct%5D=Lunara"))
        #expect(
            fragment.contains("forwardUrl=https%3A%2F%2Fapp.plex.tv%2Fdesktop%2F") ||
            fragment.contains("forwardUrl=https://app.plex.tv/desktop/")
        )
    }
}
