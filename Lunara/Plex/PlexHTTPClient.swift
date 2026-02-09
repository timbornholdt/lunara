import Foundation

struct PlexHTTPClient: PlexHTTPClienting {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send<T: Decodable>(_ request: URLRequest, decode type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        try PlexHTTPClient.validate(response: response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
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
