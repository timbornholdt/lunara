import Foundation
import CryptoKit
import os

// MARK: - Protocol

protocol LastFMClientProtocol: Sendable {
    func getToken() async throws -> String
    func getSession(token: String) async throws -> (sessionKey: String, username: String)
    func updateNowPlaying(artist: String, track: String, album: String?, duration: Int?, sessionKey: String) async throws
    func scrobble(entries: [ScrobbleEntry], sessionKey: String) async throws
    /// Cleaned plain-text artist bio (no HTML, no "Read more" boilerplate), or
    /// nil when Last.fm has none (Lunara-uww.6.1).
    func getArtistBio(artist: String) async throws -> String?
}

struct ScrobbleEntry: Codable, Equatable, Sendable {
    let artist: String
    let track: String
    let album: String?
    let timestamp: Int
    let duration: Int?
}

// MARK: - Implementation

final class LastFMClient: LastFMClientProtocol, @unchecked Sendable {

    static var apiKey: String {
        loadConfig(key: "LASTFM_API_KEY") ?? ""
    }

    static var apiSecret: String {
        loadConfig(key: "LASTFM_API_SECRET") ?? ""
    }

    private let session: URLSession
    private let apiKey: String
    private let apiSecret: String
    private let baseURL = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "LastFMClient")

    init(
        session: URLSession = .shared,
        apiKey: String = LastFMClient.apiKey,
        apiSecret: String = LastFMClient.apiSecret
    ) {
        self.session = session
        self.apiKey = apiKey
        self.apiSecret = apiSecret
    }

    private static func loadConfig(key: String) -> String? {
        guard let configPath = Bundle.main.path(forResource: "LocalConfig", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: configPath) as? [String: Any],
              let value = config[key] as? String else {
            return nil
        }
        return value
    }

    // MARK: - Auth

    func getToken() async throws -> String {
        let params: [String: String] = [
            "method": "auth.getToken",
            "api_key": apiKey
        ]
        let signed = signedParams(params)
        let data = try await performGET(params: signed)
        return try parseToken(data)
    }

    func getSession(token: String) async throws -> (sessionKey: String, username: String) {
        let params: [String: String] = [
            "method": "auth.getSession",
            "api_key": apiKey,
            "token": token
        ]
        let signed = signedParams(params)
        let data = try await performGET(params: signed)
        return try parseSession(data)
    }

    // MARK: - Scrobbling

    func updateNowPlaying(artist: String, track: String, album: String?, duration: Int?, sessionKey: String) async throws {
        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "api_key": apiKey,
            "sk": sessionKey,
            "artist": artist,
            "track": track
        ]
        if let album { params["album"] = album }
        if let duration { params["duration"] = String(duration) }

        let signed = signedParams(params)
        let data = try await performPOST(params: signed)
        try checkForError(data)
    }

    func scrobble(entries: [ScrobbleEntry], sessionKey: String) async throws {
        guard !entries.isEmpty else { return }

        var params: [String: String] = [
            "method": "track.scrobble",
            "api_key": apiKey,
            "sk": sessionKey
        ]

        for (i, entry) in entries.enumerated() {
            params["artist[\(i)]"] = entry.artist
            params["track[\(i)]"] = entry.track
            params["timestamp[\(i)]"] = String(entry.timestamp)
            if let album = entry.album { params["album[\(i)]"] = album }
            if let duration = entry.duration { params["duration[\(i)]"] = String(duration) }
        }

        let signed = signedParams(params)
        let data = try await performPOST(params: signed)
        try checkForError(data)
    }

    // MARK: - Artist Info

    func getArtistBio(artist: String) async throws -> String? {
        // Unsigned read method: only the API key is required, no session.
        let params: [String: String] = [
            "method": "artist.getInfo",
            "artist": artist,
            "autocorrect": "1",
            "api_key": apiKey,
            "format": "json"
        ]
        let data = try await performGET(params: params)
        return try Self.parseArtistBio(data)
    }

    /// Extracts `artist.bio.summary` and cleans it for display: drops the
    /// trailing "Read more on Last.fm" anchor, strips remaining tags, decodes
    /// common entities. Internal (not private) so parsing is unit-testable
    /// without networking.
    static func parseArtistBio(_ data: Data) throws -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorCode = json["error"] as? Int,
           let message = json["message"] as? String {
            throw LastFMError.apiError(code: errorCode, message: message)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artist = json["artist"] as? [String: Any],
              let bio = artist["bio"] as? [String: Any],
              let summary = bio["summary"] as? String else {
            return nil
        }

        var text = summary
        // Last.fm appends '<a href="...">Read more on Last.fm</a>'; cut from the anchor on.
        if let anchorRange = text.range(of: "<a href", options: .caseInsensitive) {
            text = String(text[..<anchorRange.lowerBound])
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&ouml;": "ö"]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Request Signing

    func signedParams(_ params: [String: String]) -> [String: String] {
        var result = params
        let sortedKeys = result.keys.sorted()
        var sigBase = ""
        for key in sortedKeys {
            sigBase += key
            sigBase += result[key] ?? ""
        }
        sigBase += apiSecret

        let digest = Insecure.MD5.hash(data: Data(sigBase.utf8))
        let sig = digest.map { String(format: "%02x", $0) }.joined()
        result["api_sig"] = sig
        result["format"] = "json"
        return result
    }

    // MARK: - HTTP

    private func performGET(params: [String: String]) async throws -> Data {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else { throw LastFMError.invalidRequest }

        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response)
        return data
    }

    private func performPOST(params: [String: String]) async throws -> Data {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = params.map { "\($0.key)=\(percentEncode($0.value))" }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)
        return data
    }

    private func percentEncode(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LastFMError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw LastFMError.networkError("HTTP \(http.statusCode)")
        }
    }

    // MARK: - Response Parsing

    private func parseToken(_ data: Data) throws -> String {
        try checkForError(data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else {
            throw LastFMError.invalidResponse
        }
        return token
    }

    private func parseSession(_ data: Data) throws -> (sessionKey: String, username: String) {
        try checkForError(data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let session = json["session"] as? [String: Any],
              let key = session["key"] as? String,
              let name = session["name"] as? String else {
            throw LastFMError.invalidResponse
        }
        return (key, name)
    }

    private func checkForError(_ data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorCode = json["error"] as? Int,
              let message = json["message"] as? String else {
            return
        }
        throw LastFMError.apiError(code: errorCode, message: message)
    }
}
