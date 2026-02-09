import Foundation

struct PlexPinRequestBuilder {
    let baseURL: URL
    let configuration: PlexClientConfiguration

    func makeCreatePinRequest() -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v2/pins"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "strong", value: "true")]
        var request = URLRequest(url: components?.url ?? baseURL)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        return request
    }

    func makeCheckPinRequest(id: Int, code: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v2/pins/\(id)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: configuration.clientIdentifier)
        ]
        var request = URLRequest(url: components?.url ?? baseURL)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        return request
    }

    private func applyHeaders(to request: inout URLRequest) {
        for (key, value) in configuration.defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}
