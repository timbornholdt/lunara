import Foundation
#if DEBUG
import os
#endif

struct PlexHTTPClient: PlexHTTPClienting {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send<T: Decodable>(_ request: URLRequest, decode type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        do {
            try PlexHTTPClient.validate(response: response, data: data)
        } catch {
#if DEBUG
            PlexHTTPClient.logFailure(request: request, response: response, data: data, error: error)
#endif
            throw error
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func sendData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        do {
            try PlexHTTPClient.validate(response: response, data: data)
        } catch {
#if DEBUG
            PlexHTTPClient.logFailure(request: request, response: response, data: data, error: error)
#endif
            throw error
        }
        return data
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PlexHTTPError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PlexHTTPError.httpStatus(http.statusCode, data)
        }
    }
}

enum PlexHTTPError: Error {
    case invalidResponse
    case httpStatus(Int, Data)
}

extension PlexHTTPClient {
#if DEBUG
    private static func logFailure(request: URLRequest, response: URLResponse, data: Data, error: Error) {
        let url = request.url?.absoluteString ?? "<unknown url>"
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        let body = String(data: data, encoding: .utf8) ?? ""
        let trimmed = body.count > 1000 ? String(body.prefix(1000)) + "…" : body
        let status = statusCode.map(String.init) ?? "n/a"
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "Lunara", category: "HTTP")
            .error("HTTP failure [\(status)] \(url) error=\(String(describing: error)) body=\(trimmed)")
    }
#endif
}

extension PlexHTTPError {
    var statusCode: Int? {
        switch self {
        case .httpStatus(let code, _):
            return code
        case .invalidResponse:
            return nil
        }
    }

    var isUnauthorized: Bool {
        statusCode == 401
    }
}
