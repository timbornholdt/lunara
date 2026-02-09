import Foundation

struct PlexResourcesService: PlexResourcesServicing {
    let httpClient: PlexHTTPClienting
    let requestBuilder: PlexResourcesRequestBuilder
    let parser: PlexResourcesXMLParser

    init(
        httpClient: PlexHTTPClienting,
        requestBuilder: PlexResourcesRequestBuilder,
        parser: PlexResourcesXMLParser = PlexResourcesXMLParser()
    ) {
        self.httpClient = httpClient
        self.requestBuilder = requestBuilder
        self.parser = parser
    }

    func fetchDevices(token: String) async throws -> [PlexResourceDevice] {
        let request = requestBuilder.makeRequest(token: token)
        let data = try await httpClient.sendData(request)
        return try parser.parse(data: data)
    }
}
