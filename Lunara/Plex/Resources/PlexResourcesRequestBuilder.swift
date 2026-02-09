import Foundation

struct PlexResourcesRequestBuilder {
    let baseURL: URL
    let configuration: PlexClientConfiguration

    func makeRequest(token: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/resources"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1")
        ]
        var request = URLRequest(url: components?.url ?? baseURL.appendingPathComponent("/api/resources"))
        request.httpMethod = "GET"
        configuration.defaultHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        return request
    }
}
