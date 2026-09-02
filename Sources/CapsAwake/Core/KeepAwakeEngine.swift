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
            AppLog.info("helper status: \(String(describing: status))")
        }
        switch status {
        case .notRegistered:
            if now >= nextRegisterAt {
                nextRegisterAt = now + 5
                do { try client.registerDaemon() } catch { /* retried on cadence */ }
            }
        case .requiresApproval:
            if !didOfferApproval {
                didOfferApproval = true
                client.openSystemSettingsForApproval()
            }
        case .notFound:
            break // surfaced by the error dot; reinstall required
        case .enabled:
            break
        @unknown default:
            break
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
        let started = Date()
        AppLog.info("writing disablesleep=\(enabled ? "1" : "0") (gen \(generation))")

        client.setKeepAwake(enabled) { [weak self] ok, error in
            guard let self, self.writeGeneration == generation else { return }
            self.applying = false
            let now = Date()
            if ok {
                self.lastWriteFailed = false
                AppLog.info("write ok (gen \(generation))")
                // Immediate post-write verification; never trust a bare exit 0.
                self.lastFlag = self.readFlag()
                switch self.lastFlag {
                case .enabled, .disabled:
                    self.nextReadAt = now + CapsAwakeDefaults.driftVerifyInterval
                case .unknown:
                    self.nextReadAt = now + 1
                }
                self.nextHeartbeatAt = started
                self.render(now: now, want: self.currentWant(now: now))
            } else {
                self.lastWriteFailed = true
                self.nextWriteAt = now + CapsAwakeDefaults.retryInterval
                self.nextReadAt = now + 2
                AppLog.error("write failed (gen \(generation)): \(error ?? "no detail")")
                self.render(now: now, want: self.currentWant(now: now))
            }
        }
    }

    private func sendHeartbeatIfNeeded(now: Date, want: Bool) {
        // Heartbeat only while the flag is (supposed to be) on. The helper
        // restores sleep if it ever stops hearing from us.
        guard want, lastFlag == .enabled else { return }
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
