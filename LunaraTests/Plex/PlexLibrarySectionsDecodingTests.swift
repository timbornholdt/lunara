import Foundation
import Testing
@testable import Lunara

struct PlexLibrarySectionsDecodingTests {
    @Test func decodesLibrarySections() throws {
        let json = """
        {
          "MediaContainer": {
            "size": 1,
            "Directory": [
              {
                "key": "2",
                "title": "Music",
                "type": "artist"
              }
            ]
          }
        }
        """

        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(PlexDirectoryResponse<PlexLibrarySection>.self, from: data)
        #expect(response.mediaContainer.items.count == 1)
        let section = try #require(response.mediaContainer.items.first)
        #expect(section.key == "2")
        #expect(section.title == "Music")
        #expect(section.type == "artist")
    }
}
