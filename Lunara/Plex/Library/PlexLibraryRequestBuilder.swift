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

    func makeAlbumTracksRequest(albumRatingKey: String) -> URLRequest {
        let url = baseURL.appendingPathComponent("library/metadata/\(albumRatingKey)/children")
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
