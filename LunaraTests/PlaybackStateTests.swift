import XCTest
@testable import Lunara

final class PlaybackStateTests: XCTestCase {

    // MARK: - isPlaying Tests

    func test_isPlaying_whenPlaying_returnsTrue() {
        let state = PlaybackState.playing
        XCTAssertTrue(state.isPlaying)
    }

    func test_isPlaying_whenNotPlaying_returnsFalse() {
        XCTAssertFalse(PlaybackState.idle.isPlaying)
        XCTAssertFalse(PlaybackState.buffering.isPlaying)
        XCTAssertFalse(PlaybackState.paused.isPlaying)
        XCTAssertFalse(PlaybackState.error("test").isPlaying)
    }

    // MARK: - isBuffering Tests

    func test_isBuffering_whenBuffering_returnsTrue() {
        let state = PlaybackState.buffering
        XCTAssertTrue(state.isBuffering)
    }

    func test_isBuffering_whenNotBuffering_returnsFalse() {
        XCTAssertFalse(PlaybackState.idle.isBuffering)
        XCTAssertFalse(PlaybackState.playing.isBuffering)
        XCTAssertFalse(PlaybackState.paused.isBuffering)
        XCTAssertFalse(PlaybackState.error("test").isBuffering)
    }

    // MARK: - canResume Tests

    func test_canResume_whenPaused_returnsTrue() {
        let state = PlaybackState.paused
        XCTAssertTrue(state.canResume)
    }

    func test_canResume_whenNotPaused_returnsFalse() {
        XCTAssertFalse(PlaybackState.idle.canResume)
        XCTAssertFalse(PlaybackState.buffering.canResume)
        XCTAssertFalse(PlaybackState.playing.canResume)
        XCTAssertFalse(PlaybackState.error("test").canResume)
    }

    // MARK: - hasError Tests

    func test_hasError_whenError_returnsTrue() {
        let state = PlaybackState.error("Stream failed")
        XCTAssertTrue(state.hasError)
    }

    func test_hasError_whenNotError_returnsFalse() {
        XCTAssertFalse(PlaybackState.idle.hasError)
        XCTAssertFalse(PlaybackState.buffering.hasError)
        XCTAssertFalse(PlaybackState.playing.hasError)
        XCTAssertFalse(PlaybackState.paused.hasError)
    }

    // MARK: - errorMessage Tests

    func test_errorMessage_whenError_returnsMessage() {
        let state = PlaybackState.error("Network timeout")
        XCTAssertEqual(state.errorMessage, "Network timeout")
    }

    func test_errorMessage_whenNotError_returnsNil() {
        XCTAssertNil(PlaybackState.idle.errorMessage)
        XCTAssertNil(PlaybackState.buffering.errorMessage)
        XCTAssertNil(PlaybackState.playing.errorMessage)
        XCTAssertNil(PlaybackState.paused.errorMessage)
    }

    func test_errorMessage_withEmptyString_returnsEmptyString() {
        let state = PlaybackState.error("")
        XCTAssertEqual(state.errorMessage, "")
    }

    // MARK: - Equatable Tests

    func test_equatable_sameStates_areEqual() {
        XCTAssertEqual(PlaybackState.idle, PlaybackState.idle)
        XCTAssertEqual(PlaybackState.buffering, PlaybackState.buffering)
        XCTAssertEqual(PlaybackState.playing, PlaybackState.playing)
        XCTAssertEqual(PlaybackState.paused, PlaybackState.paused)
        XCTAssertEqual(PlaybackState.error("test"), PlaybackState.error("test"))
    }

    func test_equatable_differentStates_areNotEqual() {
        XCTAssertNotEqual(PlaybackState.idle, PlaybackState.playing)
        XCTAssertNotEqual(PlaybackState.buffering, PlaybackState.paused)
        XCTAssertNotEqual(PlaybackState.error("one"), PlaybackState.error("two"))
    }

    // MARK: - State Transition Logic Tests

    func test_buffering_distinguishesFromPaused() {
        // This is critical: UI must show loading when buffering, not show pause button
        let buffering = PlaybackState.buffering
        let paused = PlaybackState.paused

        XCTAssertNotEqual(buffering, paused)
        XCTAssertTrue(buffering.isBuffering)
        XCTAssertFalse(paused.isBuffering)
        XCTAssertFalse(buffering.canResume)
        XCTAssertTrue(paused.canResume)
    }
}
