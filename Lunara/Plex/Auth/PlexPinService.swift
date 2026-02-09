import Foundation

struct PlexPinService: PlexPinServicing {
    let httpClient: PlexHTTPClienting
    let requestBuilder: PlexPinRequestBuilder

    func createPin() async throws -> PlexPin {
        let request = requestBuilder.makeCreatePinRequest()
        return try await httpClient.send(request, decode: PlexPin.self)
    }

    func checkPin(id: Int, code: String) async throws -> PlexPinStatus {
        let request = requestBuilder.makeCheckPinRequest(id: id, code: code)
        return try await httpClient.send(request, decode: PlexPinStatus.self)
    }
}
