import Foundation
import Testing
@testable import Lunara

struct PlexArtistDecodingTests {
    @Test func decodesArtistMetadata() throws {
        let json = """
        {
          "MediaContainer": {
            "size": 1,
            "Metadata": [
              {
                "ratingKey": "42",
                "title": "The National",
                "titleSort": "National",
                "summary": "A long-running band.",
                "thumb": "/library/metadata/42/thumb/123",
                "art": "/library/metadata/42/art/123",
                "country": "US",
                "Rating": 8.7,
                "userRating": 9.0,
                "albumCount": 9,
                "trackCount": 97,
                "addedAt": 1700000000,
                "updatedAt": 1700001000,
                "Genre": [
                  { "tag": "Indie Rock" },
                  { "tag": "Alternative" }
                ]
              }
            ]
          }
        }
        """

        let decoded = try PlexResponse<PlexArtist>.decode(from: json)
        let artist = try #require(decoded.mediaContainer.items.first)

        #expect(artist.ratingKey == "42")
        #expect(artist.title == "The National")
        #expect(artist.titleSort == "National")
        #expect(artist.summary == "A long-running band.")
        #expect(artist.thumb == "/library/metadata/42/thumb/123")
        #expect(artist.art == "/library/metadata/42/art/123")
        #expect(artist.country == "US")
        #expect(artist.rating == 8.7)
        #expect(artist.userRating == 9.0)
        #expect(artist.albumCount == 9)
        #expect(artist.trackCount == 97)
        #expect(artist.addedAt == 1700000000)
        #expect(artist.updatedAt == 1700001000)
        #expect(artist.genres?.map(\.tag) == ["Indie Rock", "Alternative"])
    }
}
