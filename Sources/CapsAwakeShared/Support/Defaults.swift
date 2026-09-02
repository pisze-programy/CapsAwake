import Foundation

/// Tuned values shared by app and helper, so tests and runtime never drift.
public enum CapsAwakeDefaults {
    /// How often the app re-reads the physical Caps Lock state.
    public static let capsLockPollInterval: TimeInterval = 0.25

    /// How often the app pings the helper while sleep prevention is on.
    public static let heartbeatInterval: TimeInterval = 30

    /// Helper-side watchdog: if no heartbeat arrives within this window while
    /// the flag is set, the helper restores normal sleep by itself.
    public static let watchdogTimeout: TimeInterval = 90

    /// How often the helper re-evaluates the watchdog.
    public static let watchdogTickInterval: TimeInterval = 30

    /// Delay before re-attempting a failed state change.
    public static let retryInterval: TimeInterval = 5

    /// How often the app re-verifies that the real flag still matches intent.
    public static let driftVerifyInterval: TimeInterval = 10

    /// XPC calls that exceed this are treated as the helper being dead.
    public static let xpcTimeout: TimeInterval = 6

    /// Safety: auto-restore sleep below this charge while not on AC.
    public static let lowBatteryPercent = 15
}
