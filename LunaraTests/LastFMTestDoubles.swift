import Foundation
@testable import Lunara

// MARK: - LastFMClientMock

final class LastFMClientMock: LastFMClientProtocol, @unchecked Sendable {
    var getTokenResult: Result<String, Error> = .success("mock-token")
    var getSessionResult: Result<(sessionKey: String, username: String), Error> = .success(("mock-session-key", "mock-user"))
    var updateNowPlayingError: Error?
    var scrobbleError: Error?

    private(set) var getTokenCallCount = 0
    private(set) var getSessionCalls: [String] = []
    private(set) var nowPlayingCalls: [(artist: String, track: String, album: String?, duration: Int?, sessionKey: String)] = []
    private(set) var scrobbleCalls: [(entries: [ScrobbleEntry], sessionKey: String)] = []

    func getToken() async throws -> String {
        getTokenCallCount += 1
        return try getTokenResult.get()
    }

    func getSession(token: String) async throws -> (sessionKey: String, username: String) {
        getSessionCalls.append(token)
        return try getSessionResult.get()
    }

    func updateNowPlaying(artist: String, track: String, album: String?, duration: Int?, sessionKey: String) async throws {
        nowPlayingCalls.append((artist, track, album, duration, sessionKey))
        if let error = updateNowPlayingError { throw error }
    }

    func scrobble(entries: [ScrobbleEntry], sessionKey: String) async throws {
        scrobbleCalls.append((entries, sessionKey))
        if let error = scrobbleError { throw error }
    }
}

// MARK: - URLOpenerMock

@MainActor
final class URLOpenerMock: URLOpening, @unchecked Sendable {
    private(set) var openedURLs: [URL] = []

    func openURL(_ url: URL) {
        openedURLs.append(url)
    }
}
