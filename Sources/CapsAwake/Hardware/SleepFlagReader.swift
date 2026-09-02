import Foundation
import CapsAwakeShared

/// Unprivileged read of the system `SleepDisabled` flag via `pmset -g`.
/// The app never asks the helper to *read* state — reading needs no privileges,
/// and doing it locally keeps a dead/unapproved helper from collapsing an
/// unreadable state into a misleading "off".
enum SleepFlagReader {
    static func currentState() -> SleepDisabledState {
        let outcome = ProcessRunner.run("/usr/bin/pmset", ["-g"])
        return PmsetParsing.resolveFlag(status: outcome.status, stdout: outcome.stdout)
    }
}
