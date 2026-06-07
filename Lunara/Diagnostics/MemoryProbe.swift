import Darwin
import Foundation
import os

/// Reads process memory figures. Behind a protocol so tests can inject
/// deterministic values instead of the live host process.
protocol MemoryProbing: Sendable {
    /// Resident physical footprint of this process, in bytes.
    func footprintBytes() -> UInt64
    /// Memory still available to this app before iOS terminates it, in bytes.
    /// Returns 0 on the simulator (only meaningful on device).
    func availableBytes() -> UInt64
}

struct MemoryProbe: MemoryProbing {
    func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    func availableBytes() -> UInt64 {
        UInt64(clamping: os_proc_available_memory())
    }
}
