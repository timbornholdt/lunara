import Foundation

// MARK: - URLSessionProtocol

/// Protocol wrapper for URLSession to enable mocking in tests
protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

// MARK: - URLSession Conformance

extension URLSession: URLSessionProtocol {
    // URLSession already has this method in iOS 15+, so it automatically conforms
}
