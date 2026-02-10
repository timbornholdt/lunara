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
    let albumsByCollectionKey: [String: [PlexAlbum]]
    var tracksByAlbumRatingKey: [String: [PlexTrack]] = [:]
    var error: Error?

    init(
        sections: [PlexLibrarySection],
        albums: [PlexAlbum],
        tracks: [PlexTrack],
        collections: [PlexCollection] = [],
        albumsByCollectionKey: [String: [PlexAlbum]] = [:],
        tracksByAlbumRatingKey: [String: [PlexTrack]] = [:],
        error: Error? = nil
    ) {
        self.sections = sections
        self.albums = albums
        self.tracks = tracks
        self.collections = collections
        self.albumsByCollectionKey = albumsByCollectionKey
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

    func fetchCollections(sectionId: String) async throws -> [PlexCollection] {
        if let error { throw error }
        return collections
    }

    func fetchAlbumsInCollection(sectionId: String, collectionKey: String) async throws -> [PlexAlbum] {
        if let error { throw error }
        return albumsByCollectionKey[collectionKey] ?? albums
    }
}
