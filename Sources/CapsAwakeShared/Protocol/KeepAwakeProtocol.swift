import Foundation

/// XPC interface implemented by the root helper and called by the app.
///
/// The helper runs as root (registered via `SMAppService`), so it can flip the
/// `SleepDisabled` flag with no admin prompt. A flag-based watchdog inside the
/// helper auto-restores normal sleep if the app stops checking in — the Mac
/// can never stay stuck awake if the app crashes or is force-quit.
///
/// Replies are plain ObjC-bridgeable values on purpose: `Bool?`/tri-state
/// don't bridge into XPC reply blocks. Reading the real flag needs no
/// privileges, so the app reads `pmset -g` directly instead of asking here;
/// this protocol only *changes* state and keeps the watchdog fed.
@objc public protocol KeepAwakeHelperProtocol {
    /// Enable/disable sleep prevention. `reply` gets success and, on failure,
    /// the underlying `pmset` error text.
    func setKeepAwake(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void)

    /// App heartbeat; resets the helper watchdog deadline.
    func heartbeat(withReply reply: @escaping (Bool) -> Void)

    /// Helper version string, used as a reachability / identity sanity check.
    func version(withReply reply: @escaping (String) -> Void)
}
