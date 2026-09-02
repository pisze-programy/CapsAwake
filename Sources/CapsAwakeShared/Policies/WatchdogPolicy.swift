import Foundation

/// What the helper's watchdog tick should do.
public enum WatchdogDecision: Equatable, Sendable {
    /// Flag is off — nothing to restore.
    case idle
    /// Flag is on and the app is checking in — keep holding.
    case keep
    /// Flag is on but the app has gone silent — restore normal sleep.
    case restore
}

/// State-based watchdog decisions (pure, testable).
///
/// Deliberately reads the *real* flag instead of trusting in-memory state:
/// if the daemon itself is killed and relaunched while `SleepDisabled` is set
/// and the app is also dead, a memory-only `keepAwake` would restart as false,
/// the watchdog would never arm, and the Mac would stay awake until reboot.
/// Evaluating against the actual flag self-heals across daemon restarts.
public enum WatchdogPolicy {
    public static func decide(
        flagEnabled: Bool,
        heartbeatAge: TimeInterval,
        timeout: TimeInterval
    ) -> WatchdogDecision {
        guard flagEnabled else { return .idle }
        return heartbeatAge >= timeout ? .restore : .keep
    }
}
