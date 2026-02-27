import Foundation
import os

// MARK: - GardenAPIClientProtocol

@MainActor
protocol GardenAPIClientProtocol {
    func submitTodo(artistName: String, albumName: String, plexID: String, body: String) async throws
}

// MARK: - GardenAPIClient

final class GardenAPIClient: GardenAPIClientProtocol {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSessionProtocol
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "GardenAPIClient")

    init(baseURL: URL, apiKey: String, session: URLSessionProtocol = URLSession.shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    func submitTodo(artistName: String, albumName: String, plexID: String, body: String) async throws {
        let url = baseURL.appendingPathComponent("api/v1/garden_todos")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "garden_todo": [
                "artist_name": artistName,
                "album_name": albumName,
                "plex_id": plexID,
                "body": body
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        logger.info("submitTodo: posting for '\(artistName, privacy: .public)' – '\(albumName, privacy: .public)'")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("submitTodo: network error: \(error.localizedDescription, privacy: .public)")
            throw GardenError.networkError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GardenError.serverError
        }

        switch httpResponse.statusCode {
        case 200...299:
            logger.info("submitTodo: success (\(httpResponse.statusCode))")
        case 401:
            logger.error("submitTodo: unauthorized")
            throw GardenError.unauthorized
        case 422:
            logger.error("submitTodo: validation failed")
            throw GardenError.validationFailed
        default:
            let bodyString = String(data: data, encoding: .utf8) ?? "(no body)"
            logger.error("submitTodo: server error \(httpResponse.statusCode): \(bodyString, privacy: .public)")
            throw GardenError.serverError
        }
    }
}
