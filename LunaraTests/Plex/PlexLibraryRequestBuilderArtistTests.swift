import Foundation
import Testing
@testable import Lunara

struct PlexLibraryRequestBuilderArtistTests {
    @Test func buildsArtistsRequest() {
        let config = PlexClientConfiguration(
            clientIdentifier: "client-id",
            product: "Lunara",
            version: "0.1",
            platform: "iOS"
        )
        let builder = PlexLibraryRequestBuilder(
            baseURL: URL(string: "https://plex.example.com")!,
            token: "token",
            configuration: config
        )

        let request = builder.makeArtistsRequest(sectionId: "5")

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/library/sections/5/all")
        #expect(request.url?.query == "type=8")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "token")
    }

    @Test func buildsArtistDetailRequest() {
        let config = PlexClientConfiguration(
            clientIdentifier: "client-id",
            product: "Lunara",
            version: "0.1",
            platform: "iOS"
        )
        let builder = PlexLibraryRequestBuilder(
            baseURL: URL(string: "https://plex.example.com")!,
            token: "token",
            configuration: config
        )

        let request = builder.makeArtistDetailRequest(artistRatingKey: "42")

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/library/metadata/42")
    }

    @Test func buildsAlbumDetailRequest() {
        let config = PlexClientConfiguration(
            clientIdentifier: "client-id",
            product: "Lunara",
            version: "0.1",
            platform: "iOS"
        )
        let builder = PlexLibraryRequestBuilder(
            baseURL: URL(string: "https://plex.example.com")!,
            token: "token",
            configuration: config
        )

        let request = builder.makeAlbumDetailRequest(albumRatingKey: "99")

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/library/metadata/99")
        #expect(request.url?.query == "includeFields=duration,originallyAvailableAt,year")
    }

    @Test func buildsArtistAlbumsRequest() {
        let config = PlexClientConfiguration(
            clientIdentifier: "client-id",
            product: "Lunara",
            version: "0.1",
            platform: "iOS"
        )
        let builder = PlexLibraryRequestBuilder(
            baseURL: URL(string: "https://plex.example.com")!,
            token: "token",
            configuration: config
        )

        let request = builder.makeArtistAlbumsRequest(artistRatingKey: "42")

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/library/metadata/42/children")
        #expect(request.url?.query == "includeFields=duration,originallyAvailableAt,year")
    }

    @Test func buildsArtistTracksRequest() {
        let config = PlexClientConfiguration(
            clientIdentifier: "client-id",
            product: "Lunara",
            version: "0.1",
            platform: "iOS"
        )
        let builder = PlexLibraryRequestBuilder(
            baseURL: URL(string: "https://plex.example.com")!,
            token: "token",
            configuration: config
        )

        let request = builder.makeArtistTracksRequest(artistRatingKey: "42")

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/library/metadata/42/allLeaves")
    }
}
