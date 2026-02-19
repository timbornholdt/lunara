import Foundation
import Observation

@MainActor
@Observable
final class ErrorBannerState {
    typealias WaitHandler = @Sendable (Duration) async throws -> Void

    var message: String?

    var isPresented: Bool {
        message != nil
    }

    private let defaultAutoDismissDelay: Duration
    private let waitHandler: WaitHandler
    private var dismissTask: Task<Void, Never>?
    private var presentationGeneration: UInt64 = 0

    init(
        defaultAutoDismissDelay: Duration = .seconds(4),
        waitHandler: WaitHandler? = nil
    ) {
        self.defaultAutoDismissDelay = defaultAutoDismissDelay
        self.waitHandler = waitHandler ?? { delay in
            try await Task.sleep(for: delay)
        }
    }

    func show(message: String, autoDismissAfter: Duration? = nil) {
        cancelScheduledDismiss()
        self.message = message

        let dismissDelay = autoDismissAfter ?? defaultAutoDismissDelay
        guard dismissDelay > .zero else {
            return
        }

        presentationGeneration &+= 1
        let generation = presentationGeneration
        dismissTask = Task { [waitHandler, weak self] in
            do {
                try await waitHandler(dismissDelay)
            } catch is CancellationError {
                return
            } catch {
                assertionFailure("Error banner auto-dismiss failed: \(error)")
                return
            }

            await MainActor.run {
                guard let self, self.presentationGeneration == generation else {
                    return
                }
                self.dismiss()
            }
        }
    }

    func dismiss() {
        cancelScheduledDismiss()
        message = nil
        presentationGeneration &+= 1
    }

    private func cancelScheduledDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }
}
