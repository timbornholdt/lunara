import Foundation
import Observation

/// Runs `onChange` once immediately, then again on every change to whatever
/// `@Observable` properties `read` touches, until the returned `Task` is
/// cancelled. This is the single observation primitive for the Now Playing
/// subsystem — it replaces both the recursive self-re-arming
/// `withObservationTracking` (used by the screen/bar view models) and the
/// hand-rolled `while !Task.isCancelled { … withCheckedContinuation { … } }`
/// loops (used by the bridge and scrobble manager).
///
/// The caller owns the returned `Task` and must cancel it (e.g. in `deinit`) so
/// the loop stops re-arming once the observer is gone.
@MainActor
@discardableResult
func observeRepeatedly(
    _ read: @escaping @MainActor () -> Void,
    onChange: @escaping @MainActor () async -> Void
) -> Task<Void, Never> {
    Task { @MainActor in
        while !Task.isCancelled {
            await onChange()
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    read()
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }
}
