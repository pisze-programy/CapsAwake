import XCTest
@testable import CapsAwakeShared

final class WatchdogPolicyTests: XCTestCase {
    func testIdleWhenFlagOffRegardlessOfHeartbeatAge() {
        XCTAssertEqual(
            WatchdogPolicy.decide(flagEnabled: false, heartbeatAge: 9_999, timeout: 90),
            .idle
        )
    }

    func testKeepWhenFresh() {
        XCTAssertEqual(
            WatchdogPolicy.decide(flagEnabled: true, heartbeatAge: 30, timeout: 90),
            .keep
        )
    }

    func testRestoreExactlyAtTimeout() {
        XCTAssertEqual(
            WatchdogPolicy.decide(flagEnabled: true, heartbeatAge: 90, timeout: 90),
            .restore
        )
    }

    func testRestoreWhenStale() {
        XCTAssertEqual(
            WatchdogPolicy.decide(flagEnabled: true, heartbeatAge: 91, timeout: 90),
            .restore
        )
    }

    /// The restart hole: even with no in-memory state, a stale heartbeat plus a
    /// still-set flag must yield restore.
    func testRestoreAfterDaemonRestartWhenFlagStillOn() {
        XCTAssertEqual(
            WatchdogPolicy.decide(flagEnabled: true, heartbeatAge: .greatestFiniteMagnitude, timeout: 90),
            .restore
        )
    }
}
