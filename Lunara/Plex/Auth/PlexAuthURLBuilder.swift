import Foundation

struct PlexAuthURLBuilder {
    func makeAuthURL(code: String, clientIdentifier: String, product: String) -> URL? {
        var components = URLComponents(string: "https://app.plex.tv/auth")
        components?.fragment = buildFragment(code: code, clientIdentifier: clientIdentifier, product: product)
        return components?.url
    }

    private func buildFragment(code: String, clientIdentifier: String, product: String) -> String {
        let queryItems = [
            URLQueryItem(name: "clientID", value: clientIdentifier),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "context[device][product]", value: product)
        ]
        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery ?? ""
    }
}
