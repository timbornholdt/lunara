import Foundation
import Testing
@testable import Lunara

/// Lunara-uww.6.2/6.3: MusicBrainz parsing is pure and tested without networking.
@Suite
struct MusicBrainzClientTests {
    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    // MARK: - Artist search

    @Test
    func parseArtistSearch_returnsTopHitID() throws {
        let json = """
        {"artists": [{"id": "mbid-sloan", "name": "Sloan", "score": 100}, {"id": "mbid-other", "score": 60}]}
        """
        #expect(try MusicBrainzClient.parseArtistSearch(data(json)) == "mbid-sloan")
    }

    @Test
    func parseArtistSearch_returnsNilForNoOrLowScoreMatch() throws {
        #expect(try MusicBrainzClient.parseArtistSearch(data(#"{"artists": []}"#)) == nil)
        // A weak match is worse than none: wrong artist's links/discography.
        let weak = #"{"artists": [{"id": "mbid-x", "score": 50}]}"#
        #expect(try MusicBrainzClient.parseArtistSearch(data(weak)) == nil)
    }

    // MARK: - URL relations

    @Test
    func parseArtistRelations_extractsWikidataWikipediaAndHomepage() throws {
        let json = """
        {"relations": [
            {"type": "wikidata", "url": {"resource": "https://www.wikidata.org/wiki/Q1133020"}},
            {"type": "official homepage", "url": {"resource": "https://sloanmusic.com"}},
            {"type": "purchase for download", "url": {"resource": "https://example.com/buy"}}
        ]}
        """
        let relations = try MusicBrainzClient.parseArtistRelations(data(json))
        #expect(relations.wikidataURL?.absoluteString == "https://www.wikidata.org/wiki/Q1133020")
        #expect(relations.homepageURL?.absoluteString == "https://sloanmusic.com")
        #expect(relations.wikipediaURL == nil)
    }

    // MARK: - Wikidata sitelink

    @Test
    func parseWikidataSitelink_buildsEnglishWikipediaURL() throws {
        let json = """
        {"entities": {"Q1133020": {"sitelinks": {"enwiki": {"title": "Sloan (band)"}}}}}
        """
        let url = try MusicBrainzClient.parseWikipediaURL(data(json))
        #expect(url?.absoluteString == "https://en.wikipedia.org/wiki/Sloan%20(band)")
    }

    @Test
    func parseWikidataSitelink_returnsNilWithoutEnwiki() throws {
        let json = #"{"entities": {"Q1": {"sitelinks": {}}}}"#
        #expect(try MusicBrainzClient.parseWikipediaURL(data(json)) == nil)
    }

    // MARK: - Release groups

    @Test
    func parseReleaseGroups_keepsStudioAlbumsOnly() throws {
        let json = """
        {"release-groups": [
            {"id": "rg-1", "title": "Navy Blues", "primary-type": "Album", "secondary-types": [], "first-release-date": "1998-03-10"},
            {"id": "rg-2", "title": "4 Nights at the Palais Royale", "primary-type": "Album", "secondary-types": ["Live"], "first-release-date": "1999"},
            {"id": "rg-3", "title": "Underwhelmed", "primary-type": "Single", "secondary-types": [], "first-release-date": "1992"}
        ]}
        """
        let groups = try MusicBrainzClient.parseReleaseGroups(data(json))
        #expect(groups.map(\.id) == ["rg-1"])
        #expect(groups[0].title == "Navy Blues")
        #expect(groups[0].firstReleaseYear == 1998)
    }
}
