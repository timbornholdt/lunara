import Foundation
import Testing
@testable import Lunara

struct PlexResourcesRequestBuilderTests {
    @Test func buildsResourcesRequest() throws {
        let config = PlexClientConfiguration(
            clientIdentifier: "client-id",
            product: "Lunara",
            version: "0.1",
            platform: "iOS"
        )
        let builder = PlexResourcesRequestBuilder(
            baseURL: URL(string: "https://plex.tv")!,
            configuration: config
        )

        let request = builder.makeRequest(token: "token")

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/resources")
        #expect(request.url?.query?.contains("includeHttps=1") == true)
        #expect(request.url?.query?.contains("includeRelay=1") == true)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "token")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "client-id")
    }
}
