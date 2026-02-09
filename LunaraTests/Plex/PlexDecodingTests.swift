import Foundation
import Testing
@testable import Lunara

struct PlexDecodingTests {
    @Test func decodesAlbumList() throws {
        let json = """
        {
          "MediaContainer": {
            "size": 1,
            "totalSize": 1,
            "offset": 0,
            "Metadata": [
              {
                "ratingKey": "265",
                "title": "Mandatory Fun",
                "thumb": "/library/metadata/265/thumb/1715112705",
                "art": "/library/metadata/265/art/1716801576",
                "year": 2014,
                "parentTitle": "Weird Al Yankovic",
                "summary": "A parody-packed album.",
                "rating": 8.5,
                "userRating": 9.0,
                "Genre": [
                  { "tag": "Comedy" },
                  { "tag": "Pop" }
                ],
                "Style": [
                  { "tag": "Parody" }
                ],
                "Mood": [
                  { "tag": "Playful" }
                ],
                "key": "/library/metadata/265/children"
              }
            ]
          }
        }
        """

        let response = try PlexResponse<PlexAlbum>.decode(from: json)
        #expect(response.mediaContainer.items.count == 1)
        let album = try #require(response.mediaContainer.items.first)
        #expect(album.ratingKey == "265")
        #expect(album.title == "Mandatory Fun")
        #expect(album.thumb != nil)
        #expect(album.artist == "Weird Al Yankovic")
        #expect(album.summary == "A parody-packed album.")
        #expect(album.genres?.first?.tag == "Comedy")
        #expect(album.styles?.first?.tag == "Parody")
        #expect(album.moods?.first?.tag == "Playful")
        #expect(album.rating == 8.5)
        #expect(album.userRating == 9.0)
        #expect(album.key == "/library/metadata/265/children")
    }

    @Test func decodesTrackList() throws {
        let json = """
        {
          "MediaContainer": {
            "size": 2,
            "totalSize": 2,
            "offset": 0,
            "Metadata": [
              {
                "ratingKey": "5001",
                "title": "First Track",
                "index": 1,
                "parentRatingKey": "265",
                "duration": 210000
              },
              {
                "ratingKey": "5002",
                "title": "Second Track",
                "index": 2,
                "parentRatingKey": "265",
                "duration": 205000
              }
            ]
          }
        }
        """

        let response = try PlexResponse<PlexTrack>.decode(from: json)
        #expect(response.mediaContainer.items.count == 2)
        let track = try #require(response.mediaContainer.items.first)
        #expect(track.index == 1)
        #expect(track.parentRatingKey == "265")
    }
}
