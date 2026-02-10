import Foundation

struct PlexLibraryRequestBuilder {
    let baseURL: URL
    let token: String
    let configuration: PlexClientConfiguration

    func makeLibrarySectionsRequest() -> URLRequest {
        let url = baseURL.appendingPathComponent("library/sections")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        return request
    }

    func makeAlbumsRequest(sectionId: String, offset: Int, size: Int) -> URLRequest {
        let url = baseURL.appendingPathComponent("library/sections/\(sectionId)/albums")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        request.setValue(String(offset), forHTTPHeaderField: "X-Plex-Container-Start")
        request.setValue(String(size), forHTTPHeaderField: "X-Plex-Container-Size")
        return request
    }

    func makeArtistsRequest(sectionId: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent("library/sections/\(sectionId)/all"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "type", value: "8")]
        let url = components?.url ?? baseURL.appendingPathComponent("library/sections/\(sectionId)/all")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        return request
    }

    func makeArtistsRequest(sectionId: String, offset: Int, size: Int) -> URLRequest {
        var request = makeArtistsRequest(sectionId: sectionId)
        request.setValue(String(offset), forHTTPHeaderField: "X-Plex-Container-Start")
        request.setValue(String(size), forHTTPHeaderField: "X-Plex-Container-Size")
        return request
    }

    func makeAlbumTracksRequest(albumRatingKey: String) -> URLRequest {
        let url = baseURL.appendingPathComponent("library/metadata/\(albumRatingKey)/children")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        return request
    }

    func makeAlbumDetailRequest(albumRatingKey: String) -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("library/metadata/\(albumRatingKey)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "includeFields", value: "duration,originallyAvailableAt,year")
        ]
        let url = components?.url ?? baseURL.appendingPathComponent("library/metadata/\(albumRatingKey)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        return request
    }

    func makeCollectionsRequest(sectionId: String, offset: Int, size: Int) -> URLRequest {
        let url = baseURL.appendingPathComponent("library/sections/\(sectionId)/collections")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        request.setValue(String(offset), forHTTPHeaderField: "X-Plex-Container-Start")
        request.setValue(String(size), forHTTPHeaderField: "X-Plex-Container-Size")
        return request
    }

    func makeCollectionItemsRequest(collectionKey: String, offset: Int, size: Int) -> URLRequest {
        let url = baseURL.appendingPathComponent("library/collections/\(collectionKey)/items")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        request.setValue(String(offset), forHTTPHeaderField: "X-Plex-Container-Start")
        request.setValue(String(size), forHTTPHeaderField: "X-Plex-Container-Size")
        return request
    }

    func makeArtistDetailRequest(artistRatingKey: String) -> URLRequest {
        let url = baseURL.appendingPathComponent("library/metadata/\(artistRatingKey)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        return request
    }

    func makeArtistAlbumsRequest(artistRatingKey: String) -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("library/metadata/\(artistRatingKey)/children"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "includeFields", value: "duration,originallyAvailableAt,year")
        ]
        let url = components?.url ?? baseURL.appendingPathComponent("library/metadata/\(artistRatingKey)/children")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        return request
    }

    func makeArtistAlbumsRequest(artistRatingKey: String, offset: Int, size: Int) -> URLRequest {
        var request = makeArtistAlbumsRequest(artistRatingKey: artistRatingKey)
        request.setValue(String(offset), forHTTPHeaderField: "X-Plex-Container-Start")
        request.setValue(String(size), forHTTPHeaderField: "X-Plex-Container-Size")
        return request
    }

    func makeArtistTracksRequest(artistRatingKey: String) -> URLRequest {
        let url = baseURL.appendingPathComponent("library/metadata/\(artistRatingKey)/allLeaves")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        return request
    }

    func makeArtistTracksRequest(artistRatingKey: String, offset: Int, size: Int) -> URLRequest {
        var request = makeArtistTracksRequest(artistRatingKey: artistRatingKey)
        request.setValue(String(offset), forHTTPHeaderField: "X-Plex-Container-Start")
        request.setValue(String(size), forHTTPHeaderField: "X-Plex-Container-Size")
        return request
    }

    private func applyHeaders(to request: inout URLRequest) {
        for (key, value) in configuration.defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
    }
}
