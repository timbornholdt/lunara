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
        authManager = AuthManager(keychain: mockKeychain, authAPI: nil)
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
        XCTAssertTrue(url.query?.contains("X-Plex-Token=test_token_123") ?? false)
    }

    func test_fetchAlbums_parsesXMLResponse_returnsAlbums() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = sampleAlbumsXML()

        let albums = try await client.fetchAlbums()

        XCTAssertEqual(albums.count, 2)
        XCTAssertEqual(albums[0].title, "Abbey Road")
        XCTAssertEqual(albums[0].artistName, "The Beatles")
        XCTAssertEqual(albums[0].year, 1969)
        XCTAssertEqual(albums[1].title, "Dark Side of the Moon")
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
    }

    func test_fetchTracks_includesAlbumID_inEndpoint() async throws {
        try authManager.setToken("token")
        mockSession.dataToReturn = sampleTracksXML()

        _ = try await client.fetchTracks(forAlbum: "99999")

        let url = mockSession.lastRequest!.url!
        XCTAssertTrue(url.path.contains("99999"))
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
            <Metadata ratingKey="1001" type="album" title="Abbey Road" parentTitle="The Beatles" year="1969" thumb="/library/metadata/1001/thumb" duration="2843000" leafCount="17" addedAt="1609459200" />
            <Metadata ratingKey="1002" type="album" title="Dark Side of the Moon" parentTitle="Pink Floyd" year="1973" thumb="/library/metadata/1002/thumb" duration="2580000" leafCount="10" addedAt="1609545600" />
        </MediaContainer>
        """.data(using: .utf8)!
    }

    private func sampleTracksXML() -> Data {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <MediaContainer>
            <Metadata ratingKey="2001" type="track" title="Come Together" index="1" grandparentTitle="The Beatles" duration="259000" key="/library/metadata/2001/file.mp3" />
            <Metadata ratingKey="2002" type="track" title="Something" index="2" grandparentTitle="The Beatles" duration="182000" key="/library/metadata/2002/file.mp3" />
            <Metadata ratingKey="2003" type="track" title="Here Comes The Sun" index="7" grandparentTitle="The Beatles" duration="185000" key="/library/metadata/2003/file.mp3" />
        </MediaContainer>
        """.data(using: .utf8)!
    }
}
