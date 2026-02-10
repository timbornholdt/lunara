import Foundation
import Testing
@testable import Lunara

struct PlexTrackDecodingTests {
    @Test func decodesTrackMediaParts() throws {
        let json = """
        {
          "MediaContainer": {
            "size": 1,
            "Metadata": [
              {
                "ratingKey": "1",
                "title": "Track",
                "index": 1,
                "duration": 123000,
                "Media": [
                  {
                    "Part": [
                      { "key": "/library/parts/123/file.mp3" }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(PlexResponse<PlexTrack>.self, from: data)
        let track = try #require(decoded.mediaContainer.items.first)
        let partKey = try #require(track.media?.first?.parts.first?.key)

        #expect(partKey == "/library/parts/123/file.mp3")
    }
}
