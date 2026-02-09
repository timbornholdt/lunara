import Foundation

struct PlexAuthURLBuilder {
    func makeAuthURL(code: String, clientIdentifier: String, product: String, forwardURL: URL? = nil) -> URL? {
        var components = URLComponents(string: "https://app.plex.tv/auth")
        components?.fragment = buildFragment(
            code: code,
            clientIdentifier: clientIdentifier,
            product: product,
            forwardURL: forwardURL
        )
        return components?.url
    }

    private func buildFragment(
        code: String,
        clientIdentifier: String,
        product: String,
        forwardURL: URL?
    ) -> String {
        var queryItems = [
            URLQueryItem(name: "clientID", value: clientIdentifier),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "context[device][product]", value: product)
        ]
        if let forwardURL {
            queryItems.append(URLQueryItem(name: "forwardUrl", value: forwardURL.absoluteString))
        }
        var components = URLComponents()
        components.queryItems = queryItems
        let query = components.percentEncodedQuery ?? ""
        return "?\(query)"
    }
}
