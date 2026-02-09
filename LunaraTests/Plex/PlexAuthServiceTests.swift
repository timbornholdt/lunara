import Foundation
import Testing
@testable import Lunara

struct PlexAuthServiceTests {
    @Test func returnsTokenFromResponse() async throws {
        let config = PlexClientConfiguration(
            clientIdentifier: "client-id",
            product: "Lunara",
            version: "0.1",
            platform: "iOS"
        )
        let builder = PlexAuthRequestBuilder(
            baseURL: URL(string: "https://plex.tv")!,
            configuration: config
        )
        let json = """
        {
          "user": {
            "authToken": "token-123"
          }
        }
        """
        let response = try JSONDecoder().decode(PlexSignInResponse.self, from: Data(json.utf8))
        let client = StubHTTPClient(result: .success(response))
        let service = PlexAuthService(httpClient: client, requestBuilder: builder)

        let token = try await service.signIn(
            login: "user@example.com",
            password: "secret",
            verificationCode: nil,
            rememberMe: true
        )

        #expect(token == "token-123")
    }

    @Test func propagatesHTTPError() async {
        let config = PlexClientConfiguration(
            clientIdentifier: "client-id",
            product: "Lunara",
            version: "0.1",
            platform: "iOS"
        )
        let builder = PlexAuthRequestBuilder(
            baseURL: URL(string: "https://plex.tv")!,
            configuration: config
        )
        let client = StubHTTPClient(result: .failure(PlexHTTPError.httpStatus(401, Data())))
        let service = PlexAuthService(httpClient: client, requestBuilder: builder)

        do {
            _ = try await service.signIn(
                login: "user@example.com",
                password: "secret",
                verificationCode: nil,
                rememberMe: true
            )
            #expect(Bool(false), "Expected sign-in to throw")
        } catch {
            #expect((error as? PlexHTTPError)?.statusCode == 401)
        }
    }
}

private struct StubHTTPClient: PlexHTTPClienting {
    let result: Result<Any, Error>

    func send<T: Decodable>(_ request: URLRequest, decode type: T.Type) async throws -> T {
        switch result {
        case .success(let value):
            guard let typed = value as? T else {
                throw TestError()
            }
            return typed
        case .failure(let error):
            throw error
        }
    }
}

private struct TestError: Error {}
