import Foundation
import Testing
@testable import Lunara

struct PlexAuthRequestBuilderTests {
    @Test func buildsSignInRequest() throws {
        let config = PlexClientConfiguration(
            clientIdentifier: "test-client-id",
            product: "Lunara",
            version: "0.1",
            platform: "iOS"
        )
        let builder = PlexAuthRequestBuilder(
            baseURL: URL(string: "https://plex.example.com")!,
            configuration: config
        )

        let request = try builder.makeSignInRequest(
            login: "user@example.com",
            password: "secret",
            verificationCode: nil,
            rememberMe: true
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/users/signin")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == "test-client-id")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Product") == "Lunara")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Version") == "0.1")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Platform") == "iOS")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")

        let body = try #require(request.httpBody)
        let bodyString = try #require(String(data: body, encoding: .utf8))
        let params = URLQueryParser.parse(bodyString)

        #expect(params["login"] == "user@example.com")
        #expect(params["password"] == "secret")
        #expect(params["rememberMe"] == "1")
        #expect(params["verificationCode"] == nil)
    }
}

private enum URLQueryParser {
    static func parse(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            result[key] = value
        }
        return result
    }
}
