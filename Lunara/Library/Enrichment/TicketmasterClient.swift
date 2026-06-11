import Foundation
import os

/// One upcoming live event for a library artist (Lunara-uww.6.4).
struct ConcertEvent: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    /// Discovery's localDate, "yyyy-MM-dd" in the venue's timezone.
    let localDate: String
    let venueName: String?
    let cityName: String?
    let url: URL?
}

protocol TicketmasterClientProtocol: Sendable {
    /// Upcoming music events for an artist near the configured home location,
    /// soonest first. Empty when none (or the artist doesn't tour).
    func upcomingEvents(artistName: String) async throws -> [ConcertEvent]
}

/// Ticketmaster Discovery v2 client. One keyword search per artist-page visit —
/// no polling, no background work (battery). The home location is Minneapolis
/// with a 200-mile radius per the original ask; promote to a setting if it ever
/// needs to move.
actor TicketmasterClient: TicketmasterClientProtocol {
    private let session: URLSession
    private let apiKey: String
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "TicketmasterClient")

    /// Minneapolis, MN.
    private static let homeLatLong = "44.9778,-93.2650"
    private static let radiusMiles = "200"

    static var configuredAPIKey: String {
        guard let configPath = Bundle.main.path(forResource: "LocalConfig", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: configPath) as? [String: Any],
              let key = config["TICKETMASTER_CONSUMER_KEY"] as? String else {
            return ""
        }
        return key
    }

    init(session: URLSession = .shared, apiKey: String = TicketmasterClient.configuredAPIKey) {
        self.session = session
        self.apiKey = apiKey
    }

    func upcomingEvents(artistName: String) async throws -> [ConcertEvent] {
        guard !apiKey.isEmpty else { return [] }

        var components = URLComponents(string: "https://app.ticketmaster.com/discovery/v2/events.json")!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "keyword", value: artistName),
            URLQueryItem(name: "classificationName", value: "music"),
            URLQueryItem(name: "latlong", value: Self.homeLatLong),
            URLQueryItem(name: "radius", value: Self.radiusMiles),
            URLQueryItem(name: "unit", value: "miles"),
            URLQueryItem(name: "sort", value: "date,asc"),
            URLQueryItem(name: "size", value: "10")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            logger.error("Ticketmaster request failed for '\(artistName, privacy: .public)'")
            throw LibraryError.invalidResponse
        }
        return try Self.parseEvents(data)
    }

    /// Internal (not private) so parsing is unit-testable without networking.
    static func parseEvents(_ data: Data) throws -> [ConcertEvent] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embedded = json["_embedded"] as? [String: Any],
              let events = embedded["events"] as? [[String: Any]] else {
            return [] // Discovery omits _embedded entirely for zero results.
        }

        return events.compactMap { event in
            guard let id = event["id"] as? String,
                  let name = event["name"] as? String,
                  let dates = event["dates"] as? [String: Any],
                  let start = dates["start"] as? [String: Any],
                  let localDate = start["localDate"] as? String else {
                return nil
            }

            let venue = ((event["_embedded"] as? [String: Any])?["venues"] as? [[String: Any]])?.first
            return ConcertEvent(
                id: id,
                name: name,
                localDate: localDate,
                venueName: venue?["name"] as? String,
                cityName: (venue?["city"] as? [String: Any])?["name"] as? String,
                url: (event["url"] as? String).flatMap(URL.init(string:))
            )
        }
    }
}
