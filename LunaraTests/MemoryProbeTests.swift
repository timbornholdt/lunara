import Foundation
import Testing
@testable import Lunara

struct MemoryProbeTests {
    @Test
    func footprintBytes_isNonZeroForLiveProcess() {
        #expect(MemoryProbe().footprintBytes() > 0)
    }

    @Test
    func availableBytes_doesNotCrash() {
        // May be 0 on the simulator (only meaningful on device) — just exercise it.
        _ = MemoryProbe().availableBytes()
    }
}
