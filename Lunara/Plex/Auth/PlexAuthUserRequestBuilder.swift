import Foundation

struct PlexAuthUserRequestBuilder {
    let baseURL: URL
    let token: String
    let configuration: PlexClientConfiguration

    func makeUserRequest() -> URLRequest {
        let url = baseURL.appendingPathComponent("api/v2/user")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        return request
    }

    private func applyHeaders(to request: inout URLRequest) {
        for (key, value) in configuration.defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
    }
}
