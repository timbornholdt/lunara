import XCTest
@testable import Lunara

// MARK: - Mock URLSession

final class MockURLSession: URLSessionProtocol {
    var dataToReturn: Data?
    var responseToReturn: URLResponse?
    var errorToThrow: Error?
    var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request

        if let error = errorToThrow {
            throw error
        }

        let data = dataToReturn ?? Data()
        let response = responseToReturn ?? HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (data, response)
    }
}

// MARK: - PlexAPIClient Tests

final class PlexAPIClientTests: XCTestCase {

    var mockSession: MockURLSession!
    var mockKeychain: MockKeychainHelper!
    var authManager: AuthManager!
    var client: PlexAPIClient!
    let baseURL = URL(string: "http://192.168.1.100:32400")!

    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        mockKeychain = MockKeychainHelper()
        authManager = AuthManager(
            keychain: mockKeychain,
            authAPI: nil,
            debugTokenProvider: { nil }
        )
        client = PlexAPIClient(
            baseURL: baseURL,
            authManager: authManager,
            session: mockSession
        )
    }

    override func tearDown() {
        mockSession = nil
        mockKeychain = nil
        authManager = nil
        client = nil
        super.tearDown()
    }

    // MARK: - fetchAlbums() Tests

    func test_fetchAlbums_includesAuthToken_inRequest() async throws {
        try authManager.setToken("test_token_123")
        mockSession.dataToReturn = sampleAlbumsXML()

        _ = try await client.fetchAlbums()

        XCTAssertNotNil(mockSession.lastRequest)
        let url = mockSession.lastRequest!.url!
        XCTAssertEqual(url.path, "/library/sections/4/all")
        XCTAssertTrue(url.query?.contains("type=9") ?? false)
        XCTAssertTrue(url.query?.contains("X-Plex-Token=test_token_123") ?? false)
    }

    func test_fetchAlbums_parsesXMLResponse_returnsAlbums() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = sampleAlbumsXML()

        let albums = try await client.fetchAlbums()

        XCTAssertEqual(albums.count, 2)
        XCTAssertEqual(albums[0].plexID, "1001")
        XCTAssertEqual(albums[0].title, "Abbey Road")
        XCTAssertEqual(albums[0].artistName, "The Beatles")
        XCTAssertEqual(albums[0].year, 1969)
        XCTAssertEqual(albums[1].plexID, "1002")
        XCTAssertEqual(albums[1].title, "Dark Side of the Moon")
    }

    func test_fetchAlbums_parsesSummaryAndChildGenreTags() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Directory key="/library/metadata/1001/children" ratingKey="1001" type="album" title="Test Album" parentTitle="Test Artist" summary="Album review text" leafCount="2" duration="120000">
                <Genre tag="Pop/Rock" />
                <Genre tag="Electronic" />
            </Directory>
        </MediaContainer>
        """.data(using: .utf8)!

        let albums = try await client.fetchAlbums()

        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums[0].review, "Album review text")
        XCTAssertEqual(albums[0].genres, ["Pop/Rock", "Electronic"])
        XCTAssertEqual(albums[0].genre, "Pop/Rock")
    }

    func test_fetchAlbum_parsesReviewGenresStylesAndMoodsFromMetadataEndpoint() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Directory ratingKey="99438" key="/library/metadata/99438/children" type="album" title="Blackstar" parentTitle="David Bowie" summary="Detailed review" leafCount="7" duration="2461000">
                <Genre tag="Pop/Rock" />
                <Style tag="Experimental Rock" />
                <Style tag="Art Rock" />
                <Mood tag="Brooding" />
                <Mood tag="Dramatic" />
            </Directory>
        </MediaContainer>
        """.data(using: .utf8)!

        let album = try await client.fetchAlbum(id: "99438")

        XCTAssertEqual(album?.plexID, "99438")
        XCTAssertEqual(album?.review, "Detailed review")
        XCTAssertEqual(album?.genres, ["Pop/Rock"])
        XCTAssertEqual(album?.styles, ["Experimental Rock", "Art Rock"])
        XCTAssertEqual(album?.moods, ["Brooding", "Dramatic"])
    }

    func test_fetchAlbums_withMissingRatingKey_throwsInvalidResponse() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Directory key="/library/metadata/1001/children" type="album" title="Abbey Road" parentTitle="The Beatles" />
        </MediaContainer>
        """.data(using: .utf8)!

        do {
            _ = try await client.fetchAlbums()
            XCTFail("Should throw invalidResponse")
        } catch let error as LibraryError {
            if case .invalidResponse = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_fetchAlbums_with401Response_invalidatesToken() async throws {
        try authManager.setToken("invalid_token")
        mockSession.responseToReturn = HTTPURLResponse(
            url: baseURL,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )

        XCTAssertTrue(authManager.isSignedIn)

        do {
            _ = try await client.fetchAlbums()
            XCTFail("Should throw authExpired")
        } catch let error as LibraryError {
            if case .authExpired = error {
                // Expected
                XCTAssertFalse(authManager.isSignedIn)
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_fetchAlbums_with404Response_throwsResourceNotFound() async throws {
        try authManager.setToken("token")
        mockSession.responseToReturn = HTTPURLResponse(
            url: baseURL,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )

        do {
            _ = try await client.fetchAlbums()
            XCTFail("Should throw resourceNotFound")
        } catch let error as LibraryError {
            if case .resourceNotFound = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_fetchAlbums_withTimeout_throwsTimeout() async throws {
        try authManager.setToken("token")
        mockSession.responseToReturn = HTTPURLResponse(
            url: baseURL,
            statusCode: 504,
            httpVersion: nil,
            headerFields: nil
        )

        do {
            _ = try await client.fetchAlbums()
            XCTFail("Should throw timeout")
        } catch let error as LibraryError {
            if case .timeout = error {
                // Expected
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - fetchTracks() Tests

    func test_fetchTracks_parsesXMLResponse_returnsTracks() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = sampleTracksXML()

        let tracks = try await client.fetchTracks(forAlbum: "12345")

        XCTAssertEqual(tracks.count, 3)
        XCTAssertEqual(tracks[0].title, "Come Together")
        XCTAssertEqual(tracks[0].trackNumber, 1)
        XCTAssertEqual(tracks[0].artistName, "The Beatles")
        XCTAssertEqual(tracks[0].albumID, "12345")
        XCTAssertEqual(tracks[0].key, "/library/parts/11/123/file.mp3")
    }

    func test_fetchTracks_includesAlbumID_inEndpoint() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = sampleTracksXML()

        _ = try await client.fetchTracks(forAlbum: "99999")

        let url = mockSession.lastRequest!.url!
        XCTAssertTrue(url.path.contains("99999"))
    }

    func test_fetchTracks_whenTrackContainsPart_usesPartKeyForPlaybackURL() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Track ratingKey="2001" type="track" title="Come Together" index="1" grandparentTitle="The Beatles" key="/library/metadata/2001">
                <Media id="1" duration="259000">
                    <Part id="2" key="/library/parts/2/123/file.mp3" />
                </Media>
            </Track>
        </MediaContainer>
        """.data(using: .utf8)!

        let tracks = try await client.fetchTracks(forAlbum: "12345")

        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].key, "/library/parts/2/123/file.mp3")
    }

    func test_fetchTracks_prefersOriginalTitle_forCompilationTrackArtist() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Track ratingKey="2001" type="track" title="Monster Song" index="1" originalTitle="Warrant" grandparentTitle="Various Artists" key="/library/metadata/2001">
                <Media id="1" duration="259000">
                    <Part id="2" key="/library/parts/2/123/file.mp3" />
                </Media>
            </Track>
        </MediaContainer>
        """.data(using: .utf8)!

        let tracks = try await client.fetchTracks(forAlbum: "12345")

        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].artistName, "Warrant")
    }

    func test_fetchTracks_whenTrackLacksPlayablePartKey_throwsInvalidResponse() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Track ratingKey="2001" type="track" title="Come Together" index="1" grandparentTitle="The Beatles" key="/library/metadata/2001" />
        </MediaContainer>
        """.data(using: .utf8)!

        do {
            _ = try await client.fetchTracks(forAlbum: "12345")
            XCTFail("Should throw invalidResponse")
        } catch let error as LibraryError {
            if case .invalidResponse = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - fetchTrack() Tests

    func test_fetchTrack_parsesTrackMetadataResponse_returnsTrack() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Track ratingKey="2001" parentRatingKey="1001" type="track" title="Come Together" index="1" grandparentTitle="The Beatles" duration="259000" key="/library/metadata/2001">
                <Media id="1" duration="259000">
                    <Part id="11" key="/library/parts/11/123/file.mp3" />
                </Media>
            </Track>
        </MediaContainer>
        """.data(using: .utf8)!

        let track = try await client.fetchTrack(id: "2001")

        XCTAssertEqual(track?.plexID, "2001")
        XCTAssertEqual(track?.albumID, "1001")
        XCTAssertEqual(track?.title, "Come Together")
        XCTAssertEqual(track?.trackNumber, 1)
        XCTAssertEqual(track?.artistName, "The Beatles")
        XCTAssertEqual(track?.key, "/library/parts/11/123/file.mp3")
    }

    func test_fetchTrack_whenResponseHasNoTrack_returnsNil() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer />
        """.data(using: .utf8)!

        let track = try await client.fetchTrack(id: "missing")

        XCTAssertNil(track)
    }

    // MARK: - Catalog Metadata Tests

    func test_fetchArtists_parsesArtistDirectories() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Directory key="100" ratingKey="100" type="artist" title="The Beatles" titleSort="Beatles, The" thumb="/library/metadata/100/thumb" genre="Rock" summary="Liverpool" leafCount="12" />
            <Directory key="200" ratingKey="200" type="artist" title="Miles Davis" leafCount="8" />
        </MediaContainer>
        """.data(using: .utf8)!

        let artists = try await client.fetchArtists()

        XCTAssertEqual(artists.map(\.plexID), ["100", "200"])
        XCTAssertEqual(artists.first?.name, "The Beatles")
        XCTAssertEqual(artists.first?.sortName, "Beatles, The")
        XCTAssertEqual(artists.first?.albumCount, 12)
    }

    func test_fetchCollections_parsesCollectionDirectories() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Directory key="300" ratingKey="300" type="collection" title="Current Vibes" thumb="/library/metadata/300/thumb" summary="Mood set" leafCount="5" updatedAt="1700001000" />
        </MediaContainer>
        """.data(using: .utf8)!

        let collections = try await client.fetchCollections()

        XCTAssertEqual(collections.count, 1)
        XCTAssertEqual(collections.first?.plexID, "300")
        XCTAssertEqual(collections.first?.title, "Current Vibes")
        XCTAssertEqual(collections.first?.albumCount, 5)
        XCTAssertEqual(collections.first?.updatedAt, Date(timeIntervalSince1970: 1700001000))
    }

    func test_fetchPlaylists_parsesPlaylistMetadata() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Playlist ratingKey="playlist-1" type="playlist" title="Morning Mix" leafCount="4" updatedAt="1700002000" />
        </MediaContainer>
        """.data(using: .utf8)!

        let playlists = try await client.fetchPlaylists()

        XCTAssertEqual(playlists.count, 1)
        XCTAssertEqual(playlists.first?.plexID, "playlist-1")
        XCTAssertEqual(playlists.first?.title, "Morning Mix")
        XCTAssertEqual(playlists.first?.trackCount, 4)
    }

    func test_fetchPlaylistItems_preservesReturnedOrder() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Track ratingKey="track-2" type="track" title="Second" />
            <Track ratingKey="track-1" type="track" title="First" />
        </MediaContainer>
        """.data(using: .utf8)!

        let items = try await client.fetchPlaylistItems(playlistID: "playlist-1")

        XCTAssertEqual(items, [
            LibraryRemotePlaylistItem(trackID: "track-2", position: 0),
            LibraryRemotePlaylistItem(trackID: "track-1", position: 1)
        ])
    }

    // MARK: - streamURL() Tests

    func test_streamURL_returnsValidURL_withToken() async throws {
        try authManager.setToken("stream_token")
        let track = Track(
            plexID: "1",
            albumID: "100",
            title: "Test Track",
            trackNumber: 1,
            duration: 180,
            artistName: "Artist",
            key: "/library/metadata/1/file.mp3",
            thumbURL: nil
        )

        let url = try await client.streamURL(forTrack: track)

        XCTAssertTrue(url.absoluteString.contains("stream_token"))
        XCTAssertTrue(url.path.contains("file.mp3"))
    }

    // MARK: - OAuth Methods Tests

    func test_requestPin_returnsPin() async throws {
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <pin id="12345" code="WXYZ" authToken="" />
        """.data(using: .utf8)

        let pin = try await client.requestPin()

        XCTAssertEqual(pin.id, 12345)
        XCTAssertEqual(pin.code, "WXYZ")
    }

    func test_checkPin_returnsToken_whenAuthorized() async throws {
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <pin id="12345" code="WXYZ" authToken="authorized_token_abc" />
        """.data(using: .utf8)

        let token = try await client.checkPin(pinID: 12345)

        XCTAssertEqual(token, "authorized_token_abc")
    }

    func test_checkPin_returnsNil_whenNotYetAuthorized() async throws {
        mockSession.dataToReturn = """
        <?xml version="1.0" encoding="UTF-8"?>
        <pin id="12345" code="WXYZ" authToken="" />
        """.data(using: .utf8)

        let token = try await client.checkPin(pinID: 12345)

        XCTAssertNil(token)
    }

    // MARK: - Client Headers Tests

    func test_allRequests_includeClientHeaders() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = sampleAlbumsXML()

        _ = try await client.fetchAlbums()

        let headers = mockSession.lastRequest!.allHTTPHeaderFields ?? [:]
        XCTAssertEqual(headers["X-Plex-Client-Identifier"], "Lunara-iOS")
        XCTAssertEqual(headers["X-Plex-Product"], "Lunara")
        XCTAssertNotNil(headers["X-Plex-Version"])
    }

    // MARK: - Sample XML Data

    private func sampleAlbumsXML() -> Data {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Directory key="1001" ratingKey="1001" type="album" title="Abbey Road" parentTitle="The Beatles" year="1969" thumb="/library/metadata/1001/thumb" duration="2843000" leafCount="17" addedAt="1609459200" />
            <Directory key="1002" ratingKey="1002" type="album" title="Dark Side of the Moon" parentTitle="Pink Floyd" year="1973" thumb="/library/metadata/1002/thumb" duration="2580000" leafCount="10" addedAt="1609545600" />
        </MediaContainer>
        """.data(using: .utf8)!
    }

    private func sampleTracksXML() -> Data {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Track ratingKey="2001" type="track" title="Come Together" index="1" grandparentTitle="The Beatles" duration="259000" key="/library/metadata/2001/file.mp3">
                <Media id="1" duration="259000">
                    <Part id="11" key="/library/parts/11/123/file.mp3" />
                </Media>
            </Track>
            <Track ratingKey="2002" type="track" title="Something" index="2" grandparentTitle="The Beatles" duration="182000" key="/library/metadata/2002/file.mp3">
                <Media id="2" duration="182000">
                    <Part id="22" key="/library/parts/22/123/file.mp3" />
                </Media>
            </Track>
            <Track ratingKey="2003" type="track" title="Here Comes The Sun" index="7" grandparentTitle="The Beatles" duration="185000" key="/library/metadata/2003/file.mp3">
                <Media id="3" duration="185000">
                    <Part id="33" key="/library/parts/33/123/file.mp3" />
                </Media>
            </Track>
        </MediaContainer>
        """.data(using: .utf8)!
    }
}
