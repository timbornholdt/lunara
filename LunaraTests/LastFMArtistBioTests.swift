import Foundation
import Testing
@testable import Lunara

/// Lunara-uww.6.1: Last.fm artist bios fill in for artists whose Plex summary
/// is empty. Parsing is pure (no networking) so it's tested directly.
@Suite
struct LastFMArtistBioParsingTests {
    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    @Test
    func parseArtistBio_stripsReadMoreLinkAndTags() throws {
        let json = """
        {"artist": {"name": "Sloan", "bio": {"summary": "Sloan is a <b>Canadian</b> rock band. <a href=\\"https://www.last.fm/music/Sloan\\">Read more on Last.fm</a>"}}}
        """
        let bio = try LastFMClient.parseArtistBio(data(json))
        #expect(bio == "Sloan is a Canadian rock band.")
    }

    @Test
    func parseArtistBio_decodesCommonEntities() throws {
        let json = """
        {"artist": {"bio": {"summary": "Mot&amp;ouml;rhead &quot;rocks&quot; &amp; rolls"}}}
        """
        let bio = try LastFMClient.parseArtistBio(data(json))
        #expect(bio?.contains("\"rocks\"") == true)
        #expect(bio?.contains("&quot;") == false)
    }

    @Test
    func parseArtistBio_returnsNilForMissingOrEmptyBio() throws {
        #expect(try LastFMClient.parseArtistBio(data(#"{"artist": {"name": "X"}}"#)) == nil)
        #expect(try LastFMClient.parseArtistBio(data(#"{"artist": {"bio": {"summary": "  "}}}"#)) == nil)
        // A bio that is ONLY the boilerplate link yields nil, not an empty string.
        let onlyLink = #"{"artist": {"bio": {"summary": "<a href=\"https://last.fm\">Read more on Last.fm</a>"}}}"#
        #expect(try LastFMClient.parseArtistBio(data(onlyLink)) == nil)
    }

    @Test
    func parseArtistBio_throwsOnAPIError() {
        let json = #"{"error": 6, "message": "The artist you supplied could not be found"}"#
        #expect(throws: LastFMError.self) {
            try LastFMClient.parseArtistBio(data(json))
        }
    }
}
