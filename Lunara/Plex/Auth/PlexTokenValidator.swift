import Foundation

struct PlexTokenValidator: PlexTokenValidating {
    let httpClient: PlexHTTPClienting
    let configuration: PlexClientConfiguration

    func validate(serverURL: URL, token: String) async throws {
        let builder = PlexAuthUserRequestBuilder(
            baseURL: PlexDefaults.authBaseURL,
            token: token,
            configuration: configuration
        )
        let request = builder.makeUserRequest()
        _ = try await httpClient.send(request, decode: PlexAuthUser.self)
    }
}

private struct PlexAuthUser: Decodable {}
