import Foundation
import Testing
@testable import Lunara

@Suite("GardenAPIClient")
@MainActor
struct GardenAPIClientTests {
    let baseURL = URL(string: "https://timbornholdt.com")!
    let apiKey = "test-api-key"

    private func makeClient(session: MockURLSession) -> GardenAPIClient {
        GardenAPIClient(baseURL: baseURL, apiKey: apiKey, session: session)
    }

    @Test("Successful submission sends correct request")
    func successfulSubmission() async throws {
        let session = MockURLSession()
        session.responseToReturn = HTTPURLResponse(
            url: baseURL, statusCode: 201, httpVersion: nil, headerFields: nil
        )
        session.dataToReturn = #"{"id":1,"status":"ok"}"#.data(using: .utf8)
        let client = makeClient(session: session)

        try await client.submitTodo(
            artistName: "Radiohead",
            albumName: "OK Computer",
            plexID: "12345",
            body: "Fix album art"
        )

        let request = session.lastRequest!
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://timbornholdt.com/api/v1/garden_todos")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let todo = body["garden_todo"] as! [String: String]
        #expect(todo["artist_name"] == "Radiohead")
        #expect(todo["album_name"] == "OK Computer")
        #expect(todo["plex_id"] == "12345")
        #expect(todo["body"] == "Fix album art")
    }

    @Test("401 response throws unauthorized")
    func unauthorizedResponse() async throws {
        let session = MockURLSession()
        session.responseToReturn = HTTPURLResponse(
            url: baseURL, statusCode: 401, httpVersion: nil, headerFields: nil
        )
        let client = makeClient(session: session)

        do {
            try await client.submitTodo(artistName: "A", albumName: "B", plexID: "1", body: "test")
            Issue.record("Expected GardenError.unauthorized")
        } catch let error as GardenError {
            #expect(error == .unauthorized)
        }
    }

    @Test("422 response throws validationFailed")
    func validationFailedResponse() async throws {
        let session = MockURLSession()
        session.responseToReturn = HTTPURLResponse(
            url: baseURL, statusCode: 422, httpVersion: nil, headerFields: nil
        )
        let client = makeClient(session: session)

        do {
            try await client.submitTodo(artistName: "A", albumName: "B", plexID: "1", body: "test")
            Issue.record("Expected GardenError.validationFailed")
        } catch let error as GardenError {
            #expect(error == .validationFailed)
        }
    }

    @Test("500 response throws serverError")
    func serverErrorResponse() async throws {
        let session = MockURLSession()
        session.responseToReturn = HTTPURLResponse(
            url: baseURL, statusCode: 500, httpVersion: nil, headerFields: nil
        )
        let client = makeClient(session: session)

        do {
            try await client.submitTodo(artistName: "A", albumName: "B", plexID: "1", body: "test")
            Issue.record("Expected GardenError.serverError")
        } catch let error as GardenError {
            #expect(error == .serverError)
        }
    }

    @Test("Network error throws networkError")
    func networkErrorThrown() async throws {
        let session = MockURLSession()
        session.errorToThrow = URLError(.notConnectedToInternet)
        let client = makeClient(session: session)

        do {
            try await client.submitTodo(artistName: "A", albumName: "B", plexID: "1", body: "test")
            Issue.record("Expected GardenError.networkError")
        } catch let error as GardenError {
            #expect(error == .networkError)
        }
    }
}
