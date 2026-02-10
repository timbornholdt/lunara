import Foundation
import Testing
@testable import Lunara

struct PlexLibraryRequestBuilderTests {
    @Test func buildsLibrarySectionsRequest() throws {
        let builder = makeBuilder()
        let request = builder.makeLibrarySectionsRequest()

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/library/sections")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "token")
    }

    @Test func buildsAlbumsRequestWithPagination() throws {
        let builder = makeBuilder()
        let request = builder.makeAlbumsRequest(sectionId: "12", offset: 50, size: 50)

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/library/sections/12/albums")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Start") == "50")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == "50")
    }

    @Test func buildsTracksRequest() throws {
        let builder = makeBuilder()
        let request = builder.makeAlbumTracksRequest(albumRatingKey: "265")

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/library/metadata/265/children")
    }

    @Test func buildsCollectionsRequestWithPagination() throws {
        let builder = makeBuilder()
        let request = builder.makeCollectionsRequest(sectionId: "12", offset: 100, size: 25)

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/library/sections/12/collections")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Start") == "100")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == "25")
    }

    @Test func buildsCollectionItemsRequestWithPagination() throws {
        let builder = makeBuilder()
        let request = builder.makeCollectionItemsRequest(collectionKey: "99", offset: 0, size: 50)

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/library/collections/99/items")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Start") == "0")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == "50")
    }

    private func makeBuilder() -> PlexLibraryRequestBuilder {
        let config = PlexClientConfiguration(
            clientIdentifier: "client-id",
            product: "Lunara",
            version: "0.1",
            platform: "iOS"
        )
        return PlexLibraryRequestBuilder(
            baseURL: URL(string: "https://example.plex.direct:32400")!,
            token: "token",
            configuration: config
        )
    }
}
