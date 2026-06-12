import Foundation
import Testing
@testable import Lunara

struct LibraryStoreTests {
    // MARK: - Release radar persistence (Lunara-nlo)

    @Test
    func artistNamesWithAlbumRatedAtLeast_returnsDistinctQualifyingArtists() async throws {
        let store = try LibraryStore.inMemory()
        let snapshot = LibrarySnapshot(
            albums: [
                makeRatedAlbum(id: "a1", artist: "Sloan", rating: 10),
                makeRatedAlbum(id: "a2", artist: "Sloan", rating: 9),
                makeRatedAlbum(id: "a3", artist: "Cheekface", rating: 9),
                makeRatedAlbum(id: "a4", artist: "Mediocre Band", rating: 8),
                makeRatedAlbum(id: "a5", artist: "Unrated Band", rating: nil)
            ],
            tracks: [], artists: [], collections: []
        )
        try await store.replaceLibrary(with: snapshot, refreshedAt: Date())

        let names = try await store.artistNames(withAlbumRatedAtLeast: 9)

        #expect(names.sorted() == ["Cheekface", "Sloan"])
    }

    @Test
    func radarEntries_replaceAndFetchRoundTrip() async throws {
        let store = try LibraryStore.inMemory()
        let entries = [
            RadarEntry(id: "rg-2", artistName: "Sloan", title: "Later Album", firstReleaseDate: "2026-10-01"),
            RadarEntry(id: "rg-1", artistName: "Cheekface", title: "Sooner Album", firstReleaseDate: "2026-07-01")
        ]

        try await store.replaceRadarEntries(entries)
        let fetched = try await store.radarEntries()

        // Soonest first.
        #expect(fetched.map(\.id) == ["rg-1", "rg-2"])

        // Replace fully supersedes.
        try await store.replaceRadarEntries([entries[0]])
        #expect(try await store.radarEntries().map(\.id) == ["rg-2"])
    }

    /// Lunara-be2: resolved MusicBrainz artist IDs persist so radar sweeps skip
    /// the per-artist search.
    @Test
    func artistMBID_roundTripAndOverwrite() async throws {
        let store = try LibraryStore.inMemory()

        #expect(try await store.artistMBID(name: "Sloan") == nil)

        try await store.saveArtistMBID("mb-1", name: "Sloan")
        #expect(try await store.artistMBID(name: "Sloan") == "mb-1")

        try await store.saveArtistMBID("mb-2", name: "Sloan")
        #expect(try await store.artistMBID(name: "Sloan") == "mb-2")
    }

    // MARK: - Artist enrichment cache (Lunara-ya7)

    @Test
    func artistEnrichmentCache_bioAndEnrichmentPersistIndependently() async throws {
        let store = try LibraryStore.inMemory()
        #expect(try await store.cachedArtistEnrichment(name: "Sloan") == nil)

        let enrichment = MusicBrainzArtistEnrichment(
            artistID: "mb-1",
            wikipediaURL: URL(string: "https://en.wikipedia.org/wiki/Sloan"),
            homepageURL: nil,
            albums: [ExternalReleaseGroup(id: "rg-1", title: "Smeared", firstReleaseYear: 1992, firstReleaseDate: "1992-08-01")]
        )
        try await store.saveArtistEnrichment(enrichment, name: "Sloan")
        var entry = try #require(try await store.cachedArtistEnrichment(name: "Sloan"))
        #expect(entry.enrichment == enrichment)
        #expect(entry.lastFMBio == nil)
        #expect(abs(entry.fetchedAt.timeIntervalSinceNow) < 10)

        // Bio saves don't clobber the enrichment or freshen its fetchedAt.
        let enrichedAt = entry.fetchedAt
        try await store.saveArtistLastFMBio("the bio", name: "Sloan")
        entry = try #require(try await store.cachedArtistEnrichment(name: "Sloan"))
        #expect(entry.enrichment == enrichment)
        #expect(entry.lastFMBio == "the bio")
        #expect(entry.fetchedAt == enrichedAt)
    }

    @Test
    func artistEnrichmentCache_bioOnlyRowStaysStaleForEnrichment() async throws {
        let store = try LibraryStore.inMemory()

        try await store.saveArtistLastFMBio("bio first", name: "NoMB")
        let entry = try #require(try await store.cachedArtistEnrichment(name: "NoMB"))

        #expect(entry.enrichment == nil)
        #expect(entry.lastFMBio == "bio first")
        // fetchedAt is epoch so an enrichment refresh still triggers.
        #expect(entry.fetchedAt < Date(timeIntervalSinceNow: -365 * 24 * 3600))
    }

    private func makeRatedAlbum(id: String, artist: String, rating: Int?) -> Album {
        Album(
            plexID: id, title: "Album \(id)", artistName: artist, year: nil,
            thumbURL: nil, genre: nil, rating: rating, addedAt: nil,
            trackCount: 1, duration: 100
        )
    }

    // MARK: - Collection membership writeback (Lunara-wd4)

    @Test
    func replaceAlbumIDsForCollection_persistsAndSupersedes() async throws {
        let store = try LibraryStore.inMemory()
        let snapshot = LibrarySnapshot(
            albums: [
                makeAlbum(id: "al-1", title: "One", artist: "A"),
                makeAlbum(id: "al-2", title: "Two", artist: "B"),
                makeAlbum(id: "al-3", title: "Three", artist: "C")
            ],
            tracks: [], artists: [],
            collections: [Collection(plexID: "col-1", title: "C1", thumbURL: nil, summary: nil, albumCount: 0, updatedAt: nil)]
        )
        try await store.replaceLibrary(with: snapshot, refreshedAt: Date())

        // An ID the catalog doesn't know ("al-ghost") is skipped, not fatal.
        try await store.replaceAlbumIDs(["al-1", "al-ghost", "al-2"], forCollectionID: "col-1")
        #expect(try await store.fetchAlbumIDs(forCollectionID: "col-1") == ["al-1", "al-2"])

        try await store.replaceAlbumIDs(["al-3"], forCollectionID: "col-1")
        #expect(try await store.fetchAlbumIDs(forCollectionID: "col-1") == ["al-3"])
    }

    // MARK: - Batched track fetch (Lunara-uuy)

    @Test
    func fetchTracksForAlbums_returnsAllInOneQueryOrderedWithinAlbums() async throws {
        let store = try LibraryStore.inMemory()
        let snapshot = LibrarySnapshot(
            albums: [
                makeAlbum(id: "al-1", title: "One", artist: "A"),
                makeAlbum(id: "al-2", title: "Two", artist: "B"),
                makeAlbum(id: "al-3", title: "Three", artist: "C")
            ],
            tracks: [
                makeTrack(id: "t-1b", albumID: "al-1", trackNumber: 2),
                makeTrack(id: "t-2a", albumID: "al-2", trackNumber: 1),
                makeTrack(id: "t-1a", albumID: "al-1", trackNumber: 1),
                makeTrack(id: "t-3a", albumID: "al-3", trackNumber: 1)
            ],
            artists: [],
            collections: []
        )
        try await store.replaceLibrary(with: snapshot, refreshedAt: Date())

        let tracks = try await store.fetchTracks(forAlbums: ["al-1", "al-2"])

        // Only the requested albums, each ordered by track number.
        let byAlbum = Dictionary(grouping: tracks, by: \.albumID)
        #expect(Set(byAlbum.keys) == ["al-1", "al-2"])
        #expect(byAlbum["al-1"]?.map(\.plexID) == ["t-1a", "t-1b"])
        #expect(byAlbum["al-2"]?.map(\.plexID) == ["t-2a"])
    }

    // MARK: - Loudness persistence (Lunara-ki3)

    @Test
    func loudnessLevels_roundTripOverwriteAndMissing() async throws {
        let store = try LibraryStore.inMemory()

        #expect(try await store.loudnessLevels(forTrack: "t1") == nil)

        try await store.setLoudnessLevels([0.1, 0.5, 1.0], forTrack: "t1")
        #expect(try await store.loudnessLevels(forTrack: "t1") == [0.1, 0.5, 1.0])

        try await store.setLoudnessLevels([0.2], forTrack: "t1")
        #expect(try await store.loudnessLevels(forTrack: "t1") == [0.2])
    }

    // MARK: - Track gain persistence (Lunara-7g3)

    @Test
    func trackGain_roundTripAndMissing() async throws {
        let store = try LibraryStore.inMemory()

        #expect(try await store.trackGain(forTrack: "t1") == nil)

        try await store.setTrackGain(TrackGain(gain: -4.75, albumGain: -4.75), forTrack: "t1")
        #expect(try await store.trackGain(forTrack: "t1") == TrackGain(gain: -4.75, albumGain: -4.75))
    }

    /// The two writers share a row but must never stomp each other's columns.
    @Test
    func trackGain_andLevels_upsertsDoNotStompEachOther() async throws {
        let store = try LibraryStore.inMemory()

        try await store.setTrackGain(TrackGain(gain: 7.11, albumGain: 7.11), forTrack: "t1")
        try await store.setLoudnessLevels([0.1, 0.9], forTrack: "t1")
        #expect(try await store.trackGain(forTrack: "t1") == TrackGain(gain: 7.11, albumGain: 7.11))
        #expect(try await store.loudnessLevels(forTrack: "t1") == [0.1, 0.9])

        try await store.setTrackGain(TrackGain(gain: -2.0, albumGain: -2.5), forTrack: "t1")
        #expect(try await store.loudnessLevels(forTrack: "t1") == [0.1, 0.9])
        #expect(try await store.trackGain(forTrack: "t1") == TrackGain(gain: -2.0, albumGain: -2.5))
    }

    /// A gain-first row parks an empty levels placeholder that must read as
    /// "no contour", not an empty contour.
    @Test
    func trackGain_writtenBeforeLevels_leavesContourMissing() async throws {
        let store = try LibraryStore.inMemory()

        try await store.setTrackGain(TrackGain(gain: -4.75, albumGain: nil), forTrack: "t1")

        #expect(try await store.loudnessLevels(forTrack: "t1") == nil)
        #expect(try await store.trackGain(forTrack: "t1") == TrackGain(gain: -4.75, albumGain: nil))
    }

    /// Rows whose gain columns are both NULL (pre-v15 contour rows) report nil
    /// so the repo knows to fetch.
    @Test
    func trackGain_contourOnlyRow_returnsNil() async throws {
        let store = try LibraryStore.inMemory()

        try await store.setLoudnessLevels([0.5], forTrack: "t1")

        #expect(try await store.trackGain(forTrack: "t1") == nil)
    }

    @Test
    func fetchesEmptyCollectionsFromFreshStore() async throws {
        let store = try LibraryStore.inMemory()

        let albums = try await store.fetchAlbums(page: LibraryPage(number: 1, size: 20))
        let artists = try await store.fetchArtists()
        let collections = try await store.fetchCollections()
        let lastRefresh = try await store.lastRefreshDate()

        #expect(albums.isEmpty)
        #expect(artists.isEmpty)
        #expect(collections.isEmpty)
        #expect(lastRefresh == nil)
    }

    @Test
    func replaceLibrary_persistsAndPaginatesAlbums() async throws {
        let store = try LibraryStore.inMemory()

        let snapshot = LibrarySnapshot(
            albums: [
                makeAlbum(id: "album-c", title: "Gamma", artist: "Artist C"),
                makeAlbum(id: "album-a", title: "Alpha", artist: "Artist A"),
                makeAlbum(id: "album-b", title: "Beta", artist: "Artist B")
            ],
            tracks: [],
            artists: [],
            collections: []
        )

        try await store.replaceLibrary(with: snapshot, refreshedAt: Date(timeIntervalSince1970: 1000))

        let firstPage = try await store.fetchAlbums(page: LibraryPage(number: 1, size: 2))
        let secondPage = try await store.fetchAlbums(page: LibraryPage(number: 2, size: 2))

        #expect(firstPage.map(\.plexID) == ["album-a", "album-b"])
        #expect(secondPage.map(\.plexID) == ["album-c"])
    }

    @Test
    func replaceLibrary_replacesExistingRowsAndRefreshTimestamp() async throws {
        let store = try LibraryStore.inMemory()

        let firstSnapshot = LibrarySnapshot(
            albums: [makeAlbum(id: "old-album", title: "Old", artist: "Artist")],
            tracks: [makeTrack(id: "old-track", albumID: "old-album", trackNumber: 1)],
            artists: [makeArtist(id: "old-artist", name: "Old Artist")],
            collections: [makeCollection(id: "old-collection", title: "Old Collection")]
        )
        try await store.replaceLibrary(with: firstSnapshot, refreshedAt: Date(timeIntervalSince1970: 2000))

        let secondSnapshot = LibrarySnapshot(
            albums: [makeAlbum(id: "new-album", title: "New", artist: "Artist")],
            tracks: [makeTrack(id: "new-track", albumID: "new-album", trackNumber: 1)],
            artists: [makeArtist(id: "new-artist", name: "New Artist")],
            collections: [makeCollection(id: "new-collection", title: "New Collection")]
        )
        try await store.replaceLibrary(with: secondSnapshot, refreshedAt: Date(timeIntervalSince1970: 3000))

        #expect(try await store.fetchAlbum(id: "old-album") == nil)
        #expect(try await store.fetchAlbum(id: "new-album")?.plexID == "new-album")
        #expect(try await store.fetchTracks(forAlbum: "new-album").map(\.plexID) == ["new-track"])
        #expect(try await store.fetchArtists().map(\.plexID) == ["new-artist"])
        #expect(try await store.fetchCollections().map(\.plexID) == ["new-collection"])
        #expect(try await store.lastRefreshDate() == Date(timeIntervalSince1970: 3000))
    }

    @Test
    func fetchTracks_forAlbum_returnsOnlyAlbumTracksSortedByTrackNumber() async throws {
        let store = try LibraryStore.inMemory()

        let snapshot = LibrarySnapshot(
            albums: [
                makeAlbum(id: "album-a", title: "A", artist: "Artist"),
                makeAlbum(id: "album-b", title: "B", artist: "Artist")
            ],
            tracks: [
                makeTrack(id: "track-2", albumID: "album-a", trackNumber: 2),
                makeTrack(id: "track-1", albumID: "album-a", trackNumber: 1),
                makeTrack(id: "track-b", albumID: "album-b", trackNumber: 1)
            ],
            artists: [],
            collections: []
        )

        try await store.replaceLibrary(with: snapshot, refreshedAt: Date())

        let albumATracks = try await store.fetchTracks(forAlbum: "album-a")

        #expect(albumATracks.map(\.plexID) == ["track-1", "track-2"])
    }

    @Test
    func artworkPath_roundTripsAndDeletesByCompositeKey() async throws {
        let store = try LibraryStore.inMemory()
        let key = ArtworkKey(ownerID: "album-1", ownerType: .album, variant: .thumbnail)

        try await store.setArtworkPath("/tmp/first.jpg", for: key)
        #expect(try await store.artworkPath(for: key) == "/tmp/first.jpg")

        try await store.setArtworkPath("/tmp/updated.jpg", for: key)
        #expect(try await store.artworkPath(for: key) == "/tmp/updated.jpg")

        try await store.deleteArtworkPath(for: key)
        #expect(try await store.artworkPath(for: key) == nil)
    }

    @Test
    func replaceLibrary_withRealPlexCapture_persistsSampleSnapshot() async throws {
        let store = try LibraryStore.inMemory()
        let snapshot = try fixtureSnapshot()

        try await store.replaceLibrary(with: snapshot, refreshedAt: Date(timeIntervalSince1970: 4000))

        #expect(!snapshot.isEmpty)
        #expect(!(try await store.fetchAlbums(page: LibraryPage(number: 1, size: 25))).isEmpty)
        #expect(!(try await store.fetchArtists()).isEmpty)
        #expect(!(try await store.fetchCollections()).isEmpty)

        let sampleAlbumID = try #require(snapshot.albums.first?.plexID)
        let tracks = try await store.fetchTracks(forAlbum: sampleAlbumID)
        #expect(!tracks.isEmpty)
    }

    private func fixtureSnapshot() throws -> LibrarySnapshot {
        let decoder = XMLDecoder()

        let albumsContainer = try decoder.decode(PlexMediaContainer.self, from: try fixtureData(name: "album_metadata.xml"))
        let tracksContainer = try decoder.decode(PlexMediaContainer.self, from: try fixtureData(name: "album_children.xml"))
        let collectionsContainer = try decoder.decode(PlexMediaContainer.self, from: try fixtureData(name: "plex-collections-sample.xml"))

        let albums = (albumsContainer.directories ?? []).compactMap { directory -> Album? in
            guard directory.type == "album", let albumID = directory.ratingKey, !albumID.isEmpty else { return nil }
            return Album(
                plexID: albumID,
                title: directory.title,
                artistName: directory.parentTitle ?? "Unknown Artist",
                year: directory.year,
                thumbURL: directory.thumb,
                genre: directory.genre,
                rating: directory.rating.map(Int.init),
                addedAt: directory.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                trackCount: directory.leafCount ?? 0,
                duration: directory.duration.map { TimeInterval($0) / 1000.0 } ?? 0
            )
        }

        let tracks = (tracksContainer.metadata ?? []).compactMap { metadata -> Track? in
            guard metadata.type == "track" else { return nil }
            guard let albumID = metadata.parentRatingKey, !albumID.isEmpty else { return nil }
            guard let key = metadata.key, !key.isEmpty else { return nil }
            return Track(
                plexID: metadata.ratingKey,
                albumID: albumID,
                title: metadata.title,
                trackNumber: metadata.index ?? 0,
                duration: TimeInterval(metadata.duration ?? 0) / 1000.0,
                artistName: metadata.grandparentTitle ?? metadata.parentTitle ?? "Unknown Artist",
                key: key,
                thumbURL: metadata.thumb
            )
        }

        let artists = (albumsContainer.directories ?? []).compactMap { directory -> Artist? in
            guard directory.type == "album" else { return nil }
            guard let artistID = directory.parentRatingKey, !artistID.isEmpty else { return nil }
            guard let artistName = directory.parentTitle, !artistName.isEmpty else { return nil }

            return Artist(
                plexID: artistID,
                name: artistName,
                sortName: nil,
                thumbURL: nil,
                genre: directory.genre,
                summary: nil,
                albumCount: 0
            )
        }

        let collections = (collectionsContainer.directories ?? []).compactMap { directory -> Collection? in
            guard directory.type == "collection", let collectionID = directory.ratingKey, !collectionID.isEmpty else { return nil }
            return Collection(
                plexID: collectionID,
                title: directory.title,
                thumbURL: directory.thumb,
                summary: directory.summary,
                albumCount: 0,
                updatedAt: nil
            )
        }

        return LibrarySnapshot(albums: albums, tracks: tracks, artists: artists, collections: collections)
    }

    private func fixtureData(name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = root
            .appendingPathComponent("tmp")
            .appendingPathComponent("plex-capture")
            .appendingPathComponent(name)
        return try Data(contentsOf: fixtureURL)
    }

    private func makeAlbum(id: String, title: String, artist: String) -> Album {
        Album(
            plexID: id,
            title: title,
            artistName: artist,
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 0,
            duration: 0
        )
    }

    private func makeTrack(id: String, albumID: String, trackNumber: Int) -> Track {
        Track(
            plexID: id,
            albumID: albumID,
            title: "Track \(id)",
            trackNumber: trackNumber,
            duration: 100,
            artistName: "Artist",
            key: "/library/parts/\(id)/1/file.mp3",
            thumbURL: nil
        )
    }

    private func makeArtist(id: String, name: String) -> Artist {
        Artist(
            plexID: id,
            name: name,
            sortName: nil,
            thumbURL: nil,
            genre: nil,
            summary: nil,
            albumCount: 1
        )
    }

    private func makeCollection(id: String, title: String) -> Collection {
        Collection(
            plexID: id,
            title: title,
            thumbURL: nil,
            summary: nil,
            albumCount: 1,
            updatedAt: nil
        )
    }
}
