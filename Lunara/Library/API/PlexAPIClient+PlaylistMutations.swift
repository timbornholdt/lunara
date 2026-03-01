import Foundation

extension PlexAPIClient {
    func fetchMachineIdentifier() async throws -> String {
        let request = try await buildRequest(path: "/", requiresAuth: true)
        let (data, _) = try await executeLoggedRequest(request, operation: "fetchMachineIdentifier")
        let container = try xmlDecoder.decode(PlexMediaContainer.self, from: data)
        guard let machineID = container.machineIdentifier, !machineID.isEmpty else {
            throw LibraryError.invalidResponse
        }
        return machineID
    }

    func addToPlaylist(playlistID: String, ratingKey: String) async throws {
        let machineID = try await fetchMachineIdentifier()
        let uri = "server://\(machineID)/com.plexapp.plugins.library/library/metadata/\(ratingKey)"

        var components = URLComponents()
        components.path = "/playlists/\(playlistID)/items"
        components.queryItems = [URLQueryItem(name: "uri", value: uri)]

        var request = try await buildRequest(
            path: "/playlists/\(playlistID)/items",
            queryItems: [URLQueryItem(name: "uri", value: uri)],
            requiresAuth: true
        )
        request.httpMethod = "PUT"

        let (_, _) = try await executeLoggedRequest(request, operation: "addToPlaylist[\(playlistID),\(ratingKey)]")
    }

    func removeFromPlaylist(playlistID: String, playlistItemID: String) async throws {
        var request = try await buildRequest(
            path: "/playlists/\(playlistID)/items/\(playlistItemID)",
            requiresAuth: true
        )
        request.httpMethod = "DELETE"

        let (_, _) = try await executeLoggedRequest(request, operation: "removeFromPlaylist[\(playlistID),\(playlistItemID)]")
    }
}
