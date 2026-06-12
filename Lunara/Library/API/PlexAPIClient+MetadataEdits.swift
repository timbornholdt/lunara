import Foundation

extension PlexAPIClient {
    /// Writes the user's star rating for an item back to Plex (Lunara-to3).
    /// Plex expects a 0-10 float; -1 clears the rating. Verified against
    /// python-plexapi's rate() implementation (Lunara-cw5 investigation).
    func writeUserRating(ratingKey: String, rating: Double) async throws {
        var request = try await buildRequest(
            path: "/:/rate",
            queryItems: [
                URLQueryItem(name: "key", value: ratingKey),
                URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
                URLQueryItem(name: "rating", value: String(rating))
            ],
            requiresAuth: true
        )
        request.httpMethod = "PUT"

        let (_, _) = try await executeLoggedRequest(request, operation: "writeUserRating[\(ratingKey)]")
    }
}
