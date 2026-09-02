import Foundation

/// Public view of the system `SleepDisabled` flag.
///
/// Reading is unprivileged; only *changing* the flag needs the root helper.
public enum SleepDisabledState: Equatable, Sendable {
    /// `SleepDisabled 1` observed — the Mac must not sleep.
    case enabled
    /// `SleepDisabled 0` observed, or (with a successful `pmset -g`) the flag
    /// line is absent — modern macOS omits the line when the flag is unset.
    case disabled
    /// `pmset` failed to run or printed nothing usable. Never collapse this
    /// into `disabled`: that would claim "safe to sleep" from data that says
    /// nothing of the sort.
    case unknown
}

/// What a `pmset -g` transcript says about the flag, before interpreting
/// absence. Split from `SleepDisabledState` so a caller can decide what an
/// absent line means for its context.
public enum ParsedSleepFlag: Equatable, Sendable {
    case enabled
    case disabled
    /// The key does not appear anywhere in the output.
    case absent
    /// The key appears but its value is not a clean `0`/`1`.
    case malformed
}

public enum PmsetParsing {
    /// Pure parse of `pmset -g` stdout for the `SleepDisabled` key, kept
    /// side-effect free so it can be unit-tested against captured output.
    public static func parseSleepDisabled(stdout: String) -> ParsedSleepFlag {
        for rawLine in stdout.split(whereSeparator: { $0.isNewline }) {
            let fields = rawLine.split(whereSeparator: { $0.isWhitespace })
            guard fields.first?.lowercased() == "sleepdisabled" else { continue }
            guard fields.count >= 2 else { return .malformed }
            switch fields[1] {
            case "1": return .enabled
            case "0": return .disabled
            default: return .malformed
            }
        }
        return .absent
    }

    /// Combine a process result with the parse. A non-zero exit or empty
    /// output yields `.unknown`; a clean exit with an absent flag line means
    /// the flag is off (`disabled`).
    public static func resolveFlag(status: Int32, stdout: String) -> SleepDisabledState {
        guard status == 0, !stdout.isEmpty else { return .unknown }
        switch parseSleepDisabled(stdout: stdout) {
        case .enabled: return .enabled
        case .disabled, .absent: return .disabled
        case .malformed: return .unknown
        }
    }
}
