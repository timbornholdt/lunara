import XCTest
@testable import Lunara

final class LunaraErrorTests: XCTestCase {

    // MARK: - LibraryError userMessage Tests

    func test_libraryError_plexUnreachable_hasUserMessage() {
        let error = LibraryError.plexUnreachable
        XCTAssertFalse(error.userMessage.isEmpty)
        XCTAssertTrue(error.userMessage.contains("Plex"))
    }

    func test_libraryError_authExpired_hasUserMessage() {
        let error = LibraryError.authExpired
        XCTAssertFalse(error.userMessage.isEmpty)
        XCTAssertTrue(error.userMessage.contains("sign in"))
    }

    func test_libraryError_databaseCorrupted_hasUserMessage() {
        let error = LibraryError.databaseCorrupted
        XCTAssertFalse(error.userMessage.isEmpty)
        XCTAssertTrue(error.userMessage.contains("library"))
    }

    func test_libraryError_apiError_includesStatusCode() {
        let error = LibraryError.apiError(statusCode: 404, message: "Not found")
        XCTAssertTrue(error.userMessage.contains("404"))
        XCTAssertTrue(error.userMessage.contains("Not found"))
    }

    func test_libraryError_invalidResponse_hasUserMessage() {
        let error = LibraryError.invalidResponse
        XCTAssertFalse(error.userMessage.isEmpty)
        XCTAssertTrue(error.userMessage.contains("Plex"))
    }

    func test_libraryError_resourceNotFound_includesResourceType() {
        let error = LibraryError.resourceNotFound(type: "album", id: "12345")
        XCTAssertTrue(error.userMessage.contains("Album"))
    }

    func test_libraryError_timeout_hasUserMessage() {
        let error = LibraryError.timeout
        XCTAssertFalse(error.userMessage.isEmpty)
        XCTAssertTrue(error.userMessage.contains("timeout"))
    }

    func test_libraryError_operationFailed_includesReason() {
        let error = LibraryError.operationFailed(reason: "Disk full")
        XCTAssertTrue(error.userMessage.contains("Disk full"))
    }

    // MARK: - MusicError userMessage Tests

    func test_musicError_streamFailed_includesReason() {
        let error = MusicError.streamFailed(reason: "Network unavailable")
        XCTAssertTrue(error.userMessage.contains("Network unavailable"))
    }

    func test_musicError_trackUnavailable_hasUserMessage() {
        let error = MusicError.trackUnavailable
        XCTAssertFalse(error.userMessage.isEmpty)
        XCTAssertTrue(error.userMessage.contains("track"))
    }

    func test_musicError_audioSessionFailed_hasUserMessage() {
        let error = MusicError.audioSessionFailed
        XCTAssertFalse(error.userMessage.isEmpty)
        XCTAssertTrue(error.userMessage.contains("audio"))
    }

    func test_musicError_interruptionFailed_hasUserMessage() {
        let error = MusicError.interruptionFailed
        XCTAssertFalse(error.userMessage.isEmpty)
        XCTAssertTrue(error.userMessage.contains("interrupted"))
    }

    func test_musicError_invalidURL_hasUserMessage() {
        let error = MusicError.invalidURL
        XCTAssertFalse(error.userMessage.isEmpty)
        XCTAssertTrue(error.userMessage.contains("Invalid"))
    }

    func test_musicError_queueOperationFailed_includesReason() {
        let error = MusicError.queueOperationFailed(reason: "Queue is empty")
        XCTAssertTrue(error.userMessage.contains("Queue is empty"))
    }

    func test_musicError_invalidState_includesReason() {
        let error = MusicError.invalidState(reason: "Cannot resume from idle")
        XCTAssertTrue(error.userMessage.contains("Cannot resume from idle"))
    }

    // MARK: - Protocol Conformance Tests

    func test_libraryError_conformsToLunaraError() {
        let error: any LunaraError = LibraryError.plexUnreachable
        XCTAssertFalse(error.userMessage.isEmpty)
    }

    func test_musicError_conformsToLunaraError() {
        let error: any LunaraError = MusicError.trackUnavailable
        XCTAssertFalse(error.userMessage.isEmpty)
    }

    // MARK: - Error as Error Protocol Tests

    func test_libraryError_canBeThrownAndCaught() {
        do {
            throw LibraryError.authExpired
        } catch let error as LibraryError {
            XCTAssertEqual(error, LibraryError.authExpired)
        } catch {
            XCTFail("Should catch LibraryError")
        }
    }

    func test_musicError_canBeThrownAndCaught() {
        do {
            throw MusicError.streamFailed(reason: "test")
        } catch let error as MusicError {
            if case .streamFailed(let reason) = error {
                XCTAssertEqual(reason, "test")
            } else {
                XCTFail("Should catch streamFailed case")
            }
        } catch {
            XCTFail("Should catch MusicError")
        }
    }
}
