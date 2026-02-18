import XCTest
@testable import Lunara

@MainActor
final class ErrorBannerStateTests: XCTestCase {
    func test_show_setsMessageAndMarksBannerPresented() async {
        let state = ErrorBannerState()

        state.show(message: "Network unavailable", autoDismissAfter: .zero)

        XCTAssertEqual(state.message, "Network unavailable")
        XCTAssertTrue(state.isPresented)
    }

    func test_show_withAutoDismiss_clearsMessageAfterDelay() async throws {
        let state = ErrorBannerState(defaultAutoDismissDelay: .milliseconds(30))

        state.show(message: "Stream failed")
        XCTAssertEqual(state.message, "Stream failed")

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertNil(state.message)
        XCTAssertFalse(state.isPresented)
    }

    func test_dismiss_clearsMessageImmediately() async {
        let state = ErrorBannerState()
        state.show(message: "Auth expired", autoDismissAfter: .seconds(10))

        state.dismiss()

        XCTAssertNil(state.message)
        XCTAssertFalse(state.isPresented)
    }

    func test_show_replacesExistingBannerAndCancelsPreviousDismissTimer() async throws {
        let state = ErrorBannerState()
        state.show(message: "First", autoDismissAfter: .milliseconds(40))
        state.show(message: "Second", autoDismissAfter: .milliseconds(120))

        try await Task.sleep(for: .milliseconds(70))
        XCTAssertEqual(state.message, "Second")
        XCTAssertTrue(state.isPresented)

        try await Task.sleep(for: .milliseconds(90))
        XCTAssertNil(state.message)
        XCTAssertFalse(state.isPresented)
    }
}
