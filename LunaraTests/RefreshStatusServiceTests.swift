import Foundation
import Testing
@testable import Lunara

/// Lunara-uww.5.2: one observable service owns background-refresh status,
/// replacing the token triple that was copy-pasted through AppCoordinator,
/// the tab view, and four list views.
@MainActor
struct RefreshStatusServiceTests {
    @Test
    func recordSuccess_bumpsTokenSetsDateAndClearsError() {
        let service = RefreshStatusService()
        service.recordFailure(message: "boom")

        let date = Date(timeIntervalSince1970: 42)
        service.recordSuccess(at: date)

        #expect(service.successToken == 1)
        #expect(service.lastRefreshDate == date)
        #expect(service.lastErrorMessage == nil)
    }

    @Test
    func recordFailure_bumpsTokenAndKeepsMessage() {
        let service = RefreshStatusService()

        service.recordFailure(message: "server unreachable")
        service.recordFailure(message: "still unreachable")

        #expect(service.failureToken == 2)
        #expect(service.lastErrorMessage == "still unreachable")
        #expect(service.successToken == 0)
    }
}
