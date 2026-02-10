import Foundation

struct PlexPlaybackURLBuilder: PlaybackFallbackURLBuilding {
    let baseURL: URL
    let token: String
    let configuration: PlexClientConfiguration

    func makeDirectPlayURL(partKey: String) -> URL {
        let relativePath = partKey.hasPrefix("/") ? partKey : "/\(partKey)"
        let base = URL(string: relativePath, relativeTo: baseURL) ?? baseURL
        return appendQueryItems(to: base, additionalItems: [])
    }

    func makeTranscodeURL(trackRatingKey: String) -> URL? {
        let url = baseURL.appendingPathComponent("music/:/transcode/universal/start.m3u8")
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "path", value: "/library/metadata/\(trackRatingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "musicBitrate", value: "128"),
            URLQueryItem(name: "audioCodec", value: "mp3")
        ]
        return appendQueryItems(to: url, additionalItems: queryItems)
    }

    private func appendQueryItems(to url: URL, additionalItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        var items = additionalItems
        items.append(contentsOf: clientQueryItems())
        components?.queryItems = items
        return components?.url ?? url
    }

    private func clientQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = [URLQueryItem(name: "X-Plex-Token", value: token)]
        configuration.defaultHeaders
            .filter { $0.key.hasPrefix("X-Plex-") }
            .sorted { $0.key < $1.key }
            .forEach { key, value in
                items.append(URLQueryItem(name: key, value: value))
            }
        return items
    }
}
