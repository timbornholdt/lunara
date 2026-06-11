import Foundation
import Observation

/// Single observable owner of background-refresh status. Replaces the
/// success/failure token triple that was previously copy-pasted from
/// AppCoordinator through the tab view into four list views (Lunara-uww.5.2).
/// Tokens are monotonically increasing so views can hang `.task(id:)` off them.
@MainActor
@Observable
final class RefreshStatusService {
    private(set) var successToken = 0
    private(set) var failureToken = 0
    private(set) var lastRefreshDate: Date?
    private(set) var lastErrorMessage: String?

    func recordSuccess(at date: Date) {
        successToken += 1
        lastRefreshDate = date
        lastErrorMessage = nil
    }

    func recordFailure(message: String) {
        failureToken += 1
        lastErrorMessage = message
    }
}

/// Shared guard logic for view models that react to background refreshes.
/// Conformers supply only what differs per screen — whether a foreground load
/// is in flight and how to reload — and inherit the token/threshold checks the
/// four +BackgroundRefresh extensions used to duplicate.
@MainActor
protocol BackgroundRefreshApplying: AnyObject {
    var isLoadingForBackgroundRefresh: Bool { get }
    var errorBannerState: ErrorBannerState { get }
    func reloadForBackgroundUpdate() async
}

extension BackgroundRefreshApplying {
    func applyBackgroundRefreshUpdateIfNeeded(successToken: Int) async {
        guard successToken > 0 else { return }
        guard !isLoadingForBackgroundRefresh else { return }
        await reloadForBackgroundUpdate()
    }

    func applyBackgroundRefreshFailureIfNeeded(failureToken: Int, message: String?) {
        guard failureToken > 0 else { return }
        guard let message, !message.isEmpty else { return }
        errorBannerState.show(message: message)
    }
}
