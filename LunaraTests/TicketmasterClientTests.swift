import Foundation
import Testing
@testable import Lunara

/// Lunara-uww.6.4: Ticketmaster Discovery parsing is pure and tested without
/// networking.
@Suite
struct TicketmasterClientTests {
    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    @Test
    func parseEvents_extractsNameDateVenueAndURL() throws {
        let json = """
        {"_embedded": {"events": [
            {
                "id": "ev-1",
                "name": "Sloan",
                "url": "https://www.ticketmaster.com/event/ev-1",
                "dates": {"start": {"localDate": "2026-07-01"}},
                "_embedded": {"venues": [{"name": "First Avenue", "city": {"name": "Minneapolis"}}]}
            },
            {
                "id": "ev-2",
                "name": "Sloan",
                "url": "https://www.ticketmaster.com/event/ev-2",
                "dates": {"start": {"localDate": "2026-08-15"}},
                "_embedded": {"venues": [{"name": "The Palace", "city": {"name": "St. Paul"}}]}
            }
        ]}}
        """
        let events = try TicketmasterClient.parseEvents(data(json))

        #expect(events.count == 2)
        #expect(events[0].id == "ev-1")
        #expect(events[0].venueName == "First Avenue")
        #expect(events[0].cityName == "Minneapolis")
        #expect(events[0].localDate == "2026-07-01")
        #expect(events[0].url?.absoluteString == "https://www.ticketmaster.com/event/ev-1")
    }

    @Test
    func parseEvents_returnsEmptyWhenNoEvents() throws {
        // Discovery omits _embedded entirely for zero results.
        #expect(try TicketmasterClient.parseEvents(data(#"{"page": {"totalElements": 0}}"#)).isEmpty)
    }

    @Test
    func parseEvents_skipsEventsMissingRequiredFields() throws {
        let json = """
        {"_embedded": {"events": [
            {"name": "No id or date"},
            {"id": "ev-ok", "name": "Sloan", "dates": {"start": {"localDate": "2026-07-01"}}}
        ]}}
        """
        let events = try TicketmasterClient.parseEvents(data(json))
        #expect(events.map(\.id) == ["ev-ok"])
        // Venue/url are optional — the row renders without them.
        #expect(events[0].venueName == nil)
    }
}
