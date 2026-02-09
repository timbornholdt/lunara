import Foundation

struct PlexArtworkURLBuilder {
    let baseURL: URL
    let token: String
    let maxSize: Int

    func makeTranscodedArtworkURL(artPath: String) -> URL {
        let transcodePath = "photo/:/transcode"
        var components = URLComponents(url: baseURL.appendingPathComponent(transcodePath), resolvingAgainstBaseURL: false)
        let urlValue = artPath.hasPrefix("/") ? artPath : "/\(artPath)"
        components?.queryItems = [
            URLQueryItem(name: "url", value: urlValue),
            URLQueryItem(name: "width", value: String(maxSize)),
            URLQueryItem(name: "height", value: String(maxSize)),
            URLQueryItem(name: "quality", value: "-1"),
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]
        return components?.url ?? baseURL
    }
}
