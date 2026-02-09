import Foundation

struct PlexAuthService: PlexAuthServicing {
    let httpClient: PlexHTTPClienting
    let requestBuilder: PlexAuthRequestBuilder

    func signIn(
        login: String,
        password: String,
        verificationCode: String?,
        rememberMe: Bool
    ) async throws -> String {
        let request = try requestBuilder.makeSignInRequest(
            login: login,
            password: password,
            verificationCode: verificationCode,
            rememberMe: rememberMe
        )
        let response = try await httpClient.send(request, decode: PlexSignInResponse.self)
        return response.user.authToken
    }
}
