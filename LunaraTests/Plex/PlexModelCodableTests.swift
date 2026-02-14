import Foundation
import Testing
@testable import Lunara

struct PlexModelCodableTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Test func plexTagRoundTrips() throws {
        let tag = PlexTag(tag: "Rock")
        let data = try encoder.encode(tag)
        let decoded = try decoder.decode(PlexTag.self, from: data)
        #expect(decoded == tag)
    }

    @Test func plexCollectionRoundTrips() throws {
        let collection = PlexCollection(
            ratingKey: "123",
            title: "Current Vibes",
            thumb: "/thumb/123",
            art: "/art/123",
            updatedAt: 1700000000,
            key: "/library/collections/123"
        )
        let data = try encoder.encode(collection)
        let decoded = try decoder.decode(PlexCollection.self, from: data)
        #expect(decoded == collection)
    }

    @Test func plexCollectionRoundTripsWithNils() throws {
        let collection = PlexCollection(
            ratingKey: "1",
            title: "Minimal",
            thumb: nil,
            art: nil,
            updatedAt: nil,
            key: nil
        )
        let data = try encoder.encode(collection)
        let decoded = try decoder.decode(PlexCollection.self, from: data)
        #expect(decoded == collection)
    }

    @Test func plexArtistRoundTrips() throws {
        let artist = PlexArtist(
            ratingKey: "42",
            title: "Radiohead",
            titleSort: "Radiohead",
            summary: "English rock band",
            thumb: "/thumb/42",
            art: "/art/42",
            country: "UK",
            genres: [PlexTag(tag: "Alternative"), PlexTag(tag: "Rock")],
            userRating: 9.0,
            rating: 8.5,
            albumCount: 9,
            trackCount: 120,
            addedAt: 1600000000,
            updatedAt: 1700000000
        )
        let data = try encoder.encode(artist)
        let decoded = try decoder.decode(PlexArtist.self, from: data)
        #expect(decoded == artist)
    }

    @Test func plexArtistRoundTripsWithNils() throws {
        let artist = PlexArtist(
            ratingKey: "1",
            title: "Unknown",
            titleSort: nil,
            summary: nil,
            thumb: nil,
            art: nil,
            country: nil,
            genres: nil,
            userRating: nil,
            rating: nil,
            albumCount: nil,
            trackCount: nil,
            addedAt: nil,
            updatedAt: nil
        )
        let data = try encoder.encode(artist)
        let decoded = try decoder.decode(PlexArtist.self, from: data)
        #expect(decoded == artist)
    }

    @Test func plexAlbumRoundTrips() throws {
        let album = PlexAlbum(
            ratingKey: "55",
            title: "OK Computer",
            thumb: "/thumb/55",
            art: "/art/55",
            year: 1997,
            duration: 3200000,
            originallyAvailableAt: "1997-06-16",
            artist: "Radiohead",
            titleSort: "OK Computer",
            originalTitle: nil,
            editionTitle: "Deluxe",
            guid: "plex://album/abc123",
            librarySectionID: 2,
            parentRatingKey: "42",
            studio: "Parlophone",
            summary: "Third studio album",
            genres: [PlexTag(tag: "Alternative")],
            styles: [PlexTag(tag: "Art Rock")],
            moods: [PlexTag(tag: "Melancholic")],
            rating: 9.2,
            userRating: 10.0,
            key: "/library/metadata/55/children"
        )
        let data = try encoder.encode(album)
        let decoded = try decoder.decode(PlexAlbum.self, from: data)
        #expect(decoded == album)
    }

    @Test func plexAlbumRoundTripsWithNils() throws {
        let album = PlexAlbum(
            ratingKey: "1",
            title: "Minimal",
            thumb: nil,
            art: nil,
            year: nil,
            artist: nil,
            titleSort: nil,
            originalTitle: nil,
            editionTitle: nil,
            guid: nil,
            librarySectionID: nil,
            parentRatingKey: nil,
            studio: nil,
            summary: nil,
            genres: nil,
            styles: nil,
            moods: nil,
            rating: nil,
            userRating: nil,
            key: nil
        )
        let data = try encoder.encode(album)
        let decoded = try decoder.decode(PlexAlbum.self, from: data)
        #expect(decoded == album)
    }

    @Test func plexTrackRoundTrips() throws {
        let track = PlexTrack(
            ratingKey: "100",
            title: "Paranoid Android",
            index: 2,
            parentIndex: 1,
            parentRatingKey: "55",
            duration: 384000,
            media: [
                PlexTrackMedia(parts: [PlexTrackPart(key: "/library/parts/100")])
            ],
            originalTitle: "Radiohead",
            grandparentTitle: "Radiohead"
        )
        let data = try encoder.encode(track)
        let decoded = try decoder.decode(PlexTrack.self, from: data)
        #expect(decoded == track)
    }

    @Test func plexTrackRoundTripsWithNils() throws {
        let track = PlexTrack(
            ratingKey: "1",
            title: "Minimal",
            index: nil,
            parentIndex: nil,
            parentRatingKey: nil,
            duration: nil,
            media: nil
        )
        let data = try encoder.encode(track)
        let decoded = try decoder.decode(PlexTrack.self, from: data)
        #expect(decoded == track)
    }

    @Test func plexTrackPartRoundTrips() throws {
        let part = PlexTrackPart(key: "/library/parts/42")
        let data = try encoder.encode(part)
        let decoded = try decoder.decode(PlexTrackPart.self, from: data)
        #expect(decoded == part)
    }

    @Test func plexTrackMediaRoundTrips() throws {
        let media = PlexTrackMedia(parts: [
            PlexTrackPart(key: "/library/parts/1"),
            PlexTrackPart(key: "/library/parts/2")
        ])
        let data = try encoder.encode(media)
        let decoded = try decoder.decode(PlexTrackMedia.self, from: data)
        #expect(decoded == media)
    }

    @Test func plexLibrarySectionRoundTrips() throws {
        let section = PlexLibrarySection(key: "2", title: "Music", type: "artist")
        let data = try encoder.encode(section)
        let decoded = try decoder.decode(PlexLibrarySection.self, from: data)
        #expect(decoded == section)
    }
}
