import Foundation
import Testing
@testable import Lunara

@MainActor
struct CoalescingMemoTests {
    /// A one-shot gate so a `make` closure can suspend until the test releases it,
    /// letting concurrent callers pile up on the in-flight task deterministically.
    @MainActor
    final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var isWaiting = false

        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.isWaiting = true
            }
        }

        func release() {
            let continuation = self.continuation
            self.continuation = nil
            continuation?.resume()
        }
    }

    private func waitUntil(iterations: Int = 300, _ condition: @escaping () -> Bool) async {
        for _ in 0..<iterations {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test
    func concurrentCallsForSameKeyRunMakeOnce() async {
        let memo = CoalescingMemo<String, Int>(capacity: 4)
        let gate = Gate()
        var makeCount = 0
        let make: @MainActor (String) async -> Int = { _ in
            makeCount += 1
            await gate.wait()
            return 42
        }

        async let r1 = memo.value(for: "k", make: make)
        async let r2 = memo.value(for: "k", make: make)
        async let r3 = memo.value(for: "k", make: make)

        await waitUntil { gate.isWaiting }
        gate.release()
        let results = await [r1, r2, r3]

        #expect(makeCount == 1)
        #expect(results == [42, 42, 42])
    }

    @Test
    func cachedValueIsServedWithoutRunningMakeAgain() async {
        let memo = CoalescingMemo<String, Int>(capacity: 4)
        var makeCount = 0
        let make: @MainActor (String) async -> Int = { _ in
            makeCount += 1
            return 7
        }

        _ = await memo.value(for: "k", make: make)
        let second = await memo.value(for: "k", make: make)

        #expect(makeCount == 1)
        #expect(second == 7)
    }

    @Test
    func lruEvictsBeyondCapacity() async {
        let memo = CoalescingMemo<String, Int>(capacity: 2)
        var makeCount = 0
        let make: @MainActor (String) async -> Int = { _ in
            makeCount += 1
            return makeCount
        }

        _ = await memo.value(for: "a", make: make) // count 1
        _ = await memo.value(for: "b", make: make) // count 2
        _ = await memo.value(for: "c", make: make) // count 3, evicts "a"
        #expect(memo.countForTesting == 2)

        // "a" was evicted, so it must run make again.
        _ = await memo.value(for: "a", make: make) // count 4
        #expect(makeCount == 4)
    }

    @Test
    func failedResultsAreNotCachedWhenShouldCacheRejectsThem() async {
        let memo = CoalescingMemo<String, Int?>(capacity: 4)
        var makeCount = 0
        // First call "fails" (nil), every later call succeeds.
        let make: @MainActor (String) async -> Int? = { _ in
            makeCount += 1
            return makeCount == 1 ? nil : 99
        }

        // nil is rejected by shouldCache → not memoized, so the next call re-runs make.
        let first = await memo.value(for: "k", shouldCache: { $0 != nil }, make: make)
        let second = await memo.value(for: "k", shouldCache: { $0 != nil }, make: make)
        #expect(first == nil)
        #expect(second == 99)
        #expect(makeCount == 2)

        // The success IS memoized, so a third call serves the cached value.
        let third = await memo.value(for: "k", shouldCache: { $0 != nil }, make: make)
        #expect(third == 99)
        #expect(makeCount == 2)
    }

    @Test
    func distinctKeysResolveIndependently() async {
        let memo = CoalescingMemo<String, String>(capacity: 8)
        var makeCount = 0
        let make: @MainActor (String) async -> String = { key in
            makeCount += 1
            return "v-\(key)"
        }

        let a = await memo.value(for: "a", make: make)
        let b = await memo.value(for: "b", make: make)

        #expect(a == "v-a")
        #expect(b == "v-b")
        #expect(makeCount == 2)
    }
}
