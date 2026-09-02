import Foundation
import ServiceManagement

import CapsAwakeShared


struct SafetySample {
    let batteryPercent: Int
    let onAC: Bool
    let thermalState: ProcessInfo.ThermalState
}

enum DotColor: Equatable {
    case off     // normal sleep / not holding
    case on      // SleepDisabled confirmed on — holding awake
    case error   // intent and reality disagree (helper down, safety hold, approval needed)
}

/// Why the app cannot hold the Mac awake. The UI shows an alert with a fix
/// action exactly once per reason, while the problem lasts.
enum AlertReason: Equatable {
    case requiresApproval
    case helperNotInstalled
    case applyFailed
    case safetyHold
}

struct DisplayState: Equatable {
    let dot: DotColor
    let tooltip: String
    let alert: AlertReason?
}

/// Owns every state decision on the main queue. Nothing else mutates the flag.
///
/// Invariant: at most one XPC state change is in flight (`applying`), guarded
/// by a monotonic generation so a stale completion from a superseded request
/// can never clobber a newer decision. The real flag is re-read after every
/// successful write and on a slow drift cadence, so an external change
/// (someone cleared it, a reboot reset it) self-heals instead of being
/// believed forever.
final class KeepAwakeEngine {
    private let readCaps: () -> Bool?
    private let readFlag: () -> SleepDisabledState
    private let safetySample: () -> SafetySample
    private let client: HelperClient
    private let onDisplay: (DisplayState) -> Void

    private var lastCapsOn: Bool?
    private var capsUnreadableSince: Date?
    private var lastFlag: SleepDisabledState = .unknown

    private var applying = false
    private var writeGeneration = 0
    private var lastWriteFailed = false
    /// Target of the last successful write. Used to keep the watchdog fed while
    /// we intend to hold even if a verification read races.
    private var intentOn = false
    private var lastWriteFinishedAt = Date.distantPast

    private var nextWriteAt = Date.distantPast
    private var nextReadAt = Date.distantPast
    private var nextHeartbeatAt = Date.distantPast
    private var nextSafetyAt = Date.distantPast
    private var nextHealthAt = Date.distantPast
    private var nextRegisterAt = Date.distantPast

    private var safetyHold = false
    private var didOfferApproval = false
    private var lastDisplay: DisplayState?
    private var lastLoggedHealth: SMAppService.Status?
    private var nextRepairAt = Date.distantPast

    private let unreadableCapsGrace: TimeInterval = 2

    init(
        readCaps: @escaping () -> Bool?,
        readFlag: @escaping () -> SleepDisabledState,
        safetySample: @escaping () -> SafetySample,
        client: HelperClient,
        onDisplay: @escaping (DisplayState) -> Void
    ) {
        self.readCaps = readCaps
        self.readFlag = readFlag
        self.safetySample = safetySample
        self.client = client
        self.onDisplay = onDisplay
        nextReadAt = .distantPast
        nextHealthAt = .distantPast
    }

    /// Called by the app's poll timer (~250 ms). All work is cheap: reading
    /// pmset and XPC calls are gated by due-times, never run every tick.
    func poll() {
        let now = Date()

        refreshCaps(now: now)
        refreshSafety(now: now)
        refreshHelperHealth(now: now)

        let want = currentWant(now: now)
        evaluate(now: now, want: want)
        sendHeartbeatIfNeeded(now: now, want: want)
        render(now: now, want: want)
    }

    /// Wake from sleep: drop the drift/read gates so the real state is
    /// reconciled promptly instead of waiting out the old cadence.
    func wake() {
        nextReadAt = .distantPast
        nextWriteAt = .distantPast
    }

    /// Best-effort restore of normal sleep before the process exits. Blocks the
    /// calling thread (pumping the main run loop) until the helper confirms or
    /// a short deadline passes — a lost message would otherwise leave the flag
    /// set for up to the 90 s watchdog window after a normal quit.
    func shutdownBlocking(timeout: TimeInterval = 2) {
        guard client.daemonStatus == .enabled else { return }
        var finished = false
        client.setKeepAwake(false) { _, _ in finished = true }
        let deadline = Date().addingTimeInterval(timeout)
        while !finished, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }


    private func refreshCaps(now: Date) {
        if let caps = readCaps() {
            capsUnreadableSince = nil
            lastCapsOn = caps
        } else if capsUnreadableSince == nil {
            capsUnreadableSince = now
        }
    }

    private var capsAvailableNow: Bool {
        guard let since = capsUnreadableSince else { return true }
        return Date().timeIntervalSince(since) < unreadableCapsGrace
    }

    private func refreshSafety(now: Date) {
        guard now >= nextSafetyAt else { return }
        nextSafetyAt = now + 5
        let sample = safetySample()
        if SafetyPolicy.shouldForceSleep(
            batteryPercent: sample.batteryPercent,
            onAC: sample.onAC,
            thermalState: sample.thermalState
        ) {
            if !safetyHold {
                AppLog.warning("safety hold on: battery=\(sample.batteryPercent)% ac=\(sample.onAC) thermal=\(sample.thermalState.rawValue)")
            }
            safetyHold = true
        } else if safetyHold,
                  SafetyPolicy.conditionsCleared(
                      batteryPercent: sample.batteryPercent,
                      onAC: sample.onAC,
                      thermalState: sample.thermalState
                  ) {
            safetyHold = false
            AppLog.info("safety hold cleared: battery=\(sample.batteryPercent)% ac=\(sample.onAC) thermal=\(sample.thermalState.rawValue)")
            nextWriteAt = .distantPast
            nextReadAt = .distantPast
        }
    }

    private func refreshHelperHealth(now: Date) {
        guard now >= nextHealthAt else { return }
        nextHealthAt = now + 2
        let status = client.daemonStatus
        if status != lastLoggedHealth {
            lastLoggedHealth = status
            AppLog.info("helper status: \(Self.statusName(status))")
        }
        switch status {
        case .notRegistered, .notFound:
            // notFound is the OS reporting a stale registration (e.g. after the
            // helper plist changed); re-registering is the repair path.
            if now >= nextRegisterAt {
                nextRegisterAt = now + 5
                do {
                    try client.registerDaemon()
                    AppLog.info("daemon register attempted")
                } catch {
                    AppLog.error("daemon register failed: \(error.localizedDescription)")
                }
            }
        case .requiresApproval:
            if !didOfferApproval {
                didOfferApproval = true
                client.openSystemSettingsForApproval()
            }
        case .enabled:
            break
        @unknown default:
            break
        }
    }

    private static func statusName(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }


    /// What the flag should be this instant. Fail-closed everywhere: an
    /// unreadable Caps Lock, a safety hold, or an unapproved/unreachable helper
    /// never results in *enabling* sleep prevention.
    private func currentWant(now: Date) -> Bool {
        guard capsAvailableNow else { return false }
        guard !safetyHold else { return false }
        return lastCapsOn == true
    }

    private func evaluate(now: Date, want: Bool) {
        if applying { return }

        if now >= nextReadAt {
            refreshFlag(now: now)
        }

        let needsWrite: Bool
        switch lastFlag {
        case .enabled:
            needsWrite = !want
        case .disabled:
            needsWrite = want
        case .unknown:
            needsWrite = true
        }

        guard needsWrite else { return }
        guard now >= nextWriteAt else { return }
        guard client.daemonStatus == .enabled else { return }
        beginWrite(on: want)
    }

    private func refreshFlag(now: Date) {
        nextReadAt = .distantFuture
        lastFlag = readFlag()
        switch lastFlag {
        case .unknown:
            nextReadAt = now + 1
        case .enabled, .disabled:
            nextReadAt = now + CapsAwakeDefaults.driftVerifyInterval
        }
    }

    private func beginWrite(on enabled: Bool) {
        applying = true
        writeGeneration += 1
        let generation = writeGeneration
        nextWriteAt = .distantFuture
        AppLog.info("writing disablesleep=\(enabled ? "1" : "0") (gen \(generation))")

        client.setKeepAwake(enabled) { [weak self] ok, error in
            guard let self, self.writeGeneration == generation else { return }
            self.applying = false
            let now = Date()
            self.lastWriteFinishedAt = now
            if ok {
                self.lastWriteFailed = false
                self.intentOn = enabled
                AppLog.info("write ok (gen \(generation))")
                // Immediate post-write verification; never trust a bare exit 0.
                self.lastFlag = self.readFlag()
                switch self.lastFlag {
                case .enabled, .disabled:
                    self.nextReadAt = now + CapsAwakeDefaults.driftVerifyInterval
                case .unknown:
                    self.nextReadAt = now + 1
                }
                // Allow a follow-up write if the app-side read still disagrees
                // (helper confirmed the flag, so any mismatch is a race, not a
                // failure — but keep reconciling instead of wedging forever).
                let appSideConfirmed = enabled == (self.lastFlag == .enabled)
                self.nextWriteAt = appSideConfirmed
                    ? .distantPast
                    : now + 2
                self.render(now: now, want: self.currentWant(now: now))
            } else {
                self.lastWriteFailed = true
                self.nextWriteAt = now + CapsAwakeDefaults.retryInterval
                self.nextReadAt = now + 2
                AppLog.error("write failed (gen \(generation)): \(error ?? "no detail")")
                // Log evidence: daemon is .enabled but no process answers the
                // Mach service (e.g. install booted the job out). Re-register
                // to resurrect it, throttled so a dead daemon cannot hammer.
                if self.client.daemonStatus == .enabled, now >= self.nextRepairAt {
                    self.nextRepairAt = now + 20
                    AppLog.warning("repairing helper: dead job, re-registering")
                    self.client.reregister {}
                }
                self.render(now: now, want: self.currentWant(now: now))
            }
        }
    }

    private func sendHeartbeatIfNeeded(now: Date, want: Bool) {
        // Heartbeat while we intend to hold, or while the flag is still on.
        // Keeps the helper watchdog from clearing a flag that is really set
        // just because a verification read raced. The helper still restores
        // sleep if the app ever goes silent for real.
        let shouldHold = intentOn || lastFlag == .enabled
        guard !safetyHold, shouldHold else { return }
        guard now >= nextHeartbeatAt else { return }
        nextHeartbeatAt = now + CapsAwakeDefaults.heartbeatInterval
        client.heartbeat()
    }


    private func render(now: Date, want: Bool) {
        let state: DisplayState
        if safetyHold {
            state = DisplayState(dot: .error, tooltip: Config.tooltipSafety, alert: .safetyHold)
        } else if client.daemonStatus != .enabled {
            let reason: AlertReason = client.daemonStatus == .requiresApproval
                ? .requiresApproval
                : .helperNotInstalled
            state = DisplayState(dot: .error, tooltip: Config.tooltipUnavailable, alert: reason)
        } else if !capsAvailableNow {
            state = DisplayState(dot: .error, tooltip: Config.tooltipFailed, alert: nil)
        } else if want && lastFlag == .enabled {
            state = DisplayState(dot: .on, tooltip: Config.tooltipOn, alert: nil)
        } else if want, lastFlag != .enabled,
                  now.timeIntervalSince(lastWriteFinishedAt) < 3 {
            // Very recent write whose read-back raced: keep it grey and quiet,
            // the reconciliation loop re-checks within a couple of seconds.
            state = DisplayState(dot: .off, tooltip: Config.tooltipPending, alert: nil)
        } else if want && !applying {
            state = DisplayState(dot: .error, tooltip: Config.tooltipFailed, alert: .applyFailed)
        } else if want {
            state = DisplayState(dot: .off, tooltip: Config.tooltipPending, alert: nil)
        } else {
            state = DisplayState(dot: .off, tooltip: Config.tooltipOff, alert: nil)
        }

        guard state != lastDisplay else { return }
        lastDisplay = state
        onDisplay(state)
    }
}
