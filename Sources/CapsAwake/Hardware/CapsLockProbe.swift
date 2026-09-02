import Foundation
import IOKit
import IOKit.hidsystem

/// Reads the physical Caps Lock latch state via the IOKit HID system. Reading
/// needs no Accessibility/Input Monitoring permission. The IOKit connection is
/// cached and transparently reopened once if a read fails, so a transient
/// power-management hiccup self-heals instead of wedging the poller.
final class CapsLockProbe {
    private let lock = NSLock()
    private var connection: io_connect_t = 0

    deinit {
        close()
    }

    /// - Returns: `true` when Caps Lock is latched on, `false` when off, or
    ///   `nil` when the state cannot be read at all.
    func isCapsLockOn() -> Bool? {
        lock.lock()
        defer { lock.unlock() }

        if connection == 0 {
            connection = Self.openConnection() ?? 0
        }
        guard connection != 0 else { return nil }

        var state: Bool? = Self.readState(connection)
        if state == nil {
            // Stale connection (e.g. after a sleep/wake): reopen once and retry.
            Self.closeConnection(connection)
            connection = Self.openConnection() ?? 0
            guard connection != 0 else { return nil }
            state = Self.readState(connection)
        }
        return state
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if connection != 0 {
            Self.closeConnection(connection)
            connection = 0
        }
    }

    private static func readState(_ connection: io_connect_t) -> Bool? {
        var state = false
        guard IOHIDGetModifierLockState(
            connection,
            Int32(kIOHIDCapsLockState),
            &state
        ) == KERN_SUCCESS else {
            return nil
        }
        return state
    }

    private static func openConnection() -> io_connect_t? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching(kIOHIDSystemClass)
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(
            service,
            mach_task_self_,
            UInt32(kIOHIDParamConnectType),
            &connection
        ) == KERN_SUCCESS else {
            return nil
        }
        return connection
    }

    private static func closeConnection(_ connection: io_connect_t) {
        IOServiceClose(connection)
    }
}
