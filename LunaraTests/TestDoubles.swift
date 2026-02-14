import Foundation
@testable import Lunara

final class InMemoryTokenStore: PlexAuthTokenStoring {
    var token: String?

    init(token: String?) {
        self.token = token
    }

    func save(token: String) throws {
        self.token = token
    }

    func load() throws -> String? {
        token
    }

    func clear() throws {
        token = nil
    }
}

final class InMemoryServerStore: PlexServerAddressStoring {
    var url: URL?

    init(url: URL?) {
        self.url = url
    }

    var serverURL: URL? {
        get { url }
        set { url = newValue }
    }
}

final class InMemorySelectionStore: PlexLibrarySelectionStoring {
    var key: String?

    init(key: String?) {
        self.key = key
    }

    var selectedSectionKey: String? {
        get { key }
        set { key = newValue }
    }
}

struct StubLibraryService: PlexLibraryServicing {
    let sections: [PlexLibrarySection]
    let albums: [PlexAlbum]
    let tracks: [PlexTrack]
    let collections: [PlexCollection]
    let albumDetailsByRatingKey: [String: PlexAlbum]
    let albumsByCollectionKey: [String: [PlexAlbum]]
    let artists: [PlexArtist]
    let artistDetail: PlexArtist?
    let albumsByArtistKey: [String: [PlexAlbum]]
    let tracksByArtistKey: [String: [PlexTrack]]
    var tracksByAlbumRatingKey: [String: [PlexTrack]] = [:]
    var error: Error?

    init(
        sections: [PlexLibrarySection],
        albums: [PlexAlbum],
        tracks: [PlexTrack],
        collections: [PlexCollection] = [],
        albumsByCollectionKey: [String: [PlexAlbum]] = [:],
        artists: [PlexArtist] = [],
        artistDetail: PlexArtist? = nil,
        albumsByArtistKey: [String: [PlexAlbum]] = [:],
        tracksByArtistKey: [String: [PlexTrack]] = [:],
        albumDetailsByRatingKey: [String: PlexAlbum] = [:],
        tracksByAlbumRatingKey: [String: [PlexTrack]] = [:],
        error: Error? = nil
    ) {
        self.sections = sections
        self.albums = albums
        self.tracks = tracks
        self.collections = collections
        self.albumDetailsByRatingKey = albumDetailsByRatingKey
        self.albumsByCollectionKey = albumsByCollectionKey
        self.artists = artists
        self.artistDetail = artistDetail
        self.albumsByArtistKey = albumsByArtistKey
        self.tracksByArtistKey = tracksByArtistKey
        self.tracksByAlbumRatingKey = tracksByAlbumRatingKey
        self.error = error
    }

    func fetchLibrarySections() async throws -> [PlexLibrarySection] {
        if let error { throw error }
        return sections
    }

    func fetchAlbums(sectionId: String) async throws -> [PlexAlbum] {
        if let error { throw error }
        return albums
    }

    func fetchTracks(albumRatingKey: String) async throws -> [PlexTrack] {
        if let error { throw error }
        if let keyedTracks = tracksByAlbumRatingKey[albumRatingKey] {
            return keyedTracks
        }
        return tracks
    }

    func fetchAlbumDetail(albumRatingKey: String) async throws -> PlexAlbum? {
        if let error { throw error }
        return albumDetailsByRatingKey[albumRatingKey]
    }

    func fetchCollections(sectionId: String) async throws -> [PlexCollection] {
        if let error { throw error }
        return collections
    }

    func fetchAlbumsInCollection(sectionId: String, collectionKey: String) async throws -> [PlexAlbum] {
        if let error { throw error }
        return albumsByCollectionKey[collectionKey] ?? albums
    }

    func fetchArtists(sectionId: String) async throws -> [PlexArtist] {
        if let error { throw error }
        return artists
    }

    func fetchArtistDetail(artistRatingKey: String) async throws -> PlexArtist? {
        if let error { throw error }
        return artistDetail
    }

    func fetchArtistAlbums(artistRatingKey: String) async throws -> [PlexAlbum] {
        if let error { throw error }
        return albumsByArtistKey[artistRatingKey] ?? []
    }

    func fetchArtistTracks(artistRatingKey: String) async throws -> [PlexTrack] {
        if let error { throw error }
        return tracksByArtistKey[artistRatingKey] ?? []
    }
}

final class InMemoryLibraryCacheStore: LibraryCacheStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func load<T: Decodable>(key: LibraryCacheKey, as type: T.Type) -> T? {
        guard let data = storage[key.stringValue] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func save<T: Encodable>(key: LibraryCacheKey, value: T) {
        storage[key.stringValue] = try? JSONEncoder().encode(value)
    }

    func remove(key: LibraryCacheKey) {
        storage.removeValue(forKey: key.stringValue)
    }

    func clear() {
        storage.removeAll()
    }
}

final class InMemoryAppSettingsStore: AppSettingsStoring {
    private var values: [AppSettingBoolKey: Bool]

    init(values: [AppSettingBoolKey: Bool] = [:]) {
        self.values = values
    }

    var isAlbumDedupDebugEnabled: Bool {
        get { bool(for: .albumDedupDebugLogging) }
        set { set(newValue, for: .albumDedupDebugLogging) }
    }

    func bool(for key: AppSettingBoolKey) -> Bool {
        values[key] ?? false
    }

    func set(_ value: Bool, for key: AppSettingBoolKey) {
        values[key] = value
    }
}
