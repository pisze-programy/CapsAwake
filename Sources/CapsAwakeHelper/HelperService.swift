import Foundation
import os
import CapsAwakeShared

private let log = Logger(subsystem: "com.piszeprogramy.capsawake.helper", category: "helper")

/// Accepts XPC connections from the app only. Every process on the machine can
/// reach the Mach service a launchd daemon owns, so a plain listener would let
/// any program ask a root process to hold the Mac awake indefinitely.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HelperService()
    private let requirement: String

    init(machLabel: String) {
        let appBundleID = CapsAwakeIdentity.appBundleID(fromHelperLabel: machLabel)
            ?? CapsAwakeIdentity.appBundleID
        requirement = CapsAwakeIdentity.codeSigningRequirement(appBundleID: appBundleID)
        super.init()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // Enforced against the peer's audit token on every message — no
        // PID-reuse race. Must be set before resume(); it is an error twice.
        newConnection.setCodeSigningRequirement(requirement)
        newConnection.exportedInterface = NSXPCInterface(with: KeepAwakeHelperProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}

/// The privileged work. Runs as root, so it can flip `pmset` with no prompt.
///
/// Watchdog is state-based, not memory-based: every tick re-reads the *real*
/// flag and restores sleep only when the flag is actually set and the app has
/// gone silent. If this daemon is killed and relaunched while the flag is on
/// (and the app is dead too), the fresh process adopts the flag and still
/// clears it — the Mac cannot stay stuck awake through a double failure.
final class HelperService: NSObject, KeepAwakeHelperProtocol {
    private static let versionString = "0.1.0"

    private let stateQueue = DispatchQueue(label: "com.piszeprogramy.capsawake.helper.state")
    private var lastHeartbeat = Date.distantPast
    private var watchdogTimer: DispatchSourceTimer?

    override init() {
        super.init()
        let flagOnAtStart = Self.currentFlagIsEnabled()
        if flagOnAtStart {
            // Fresh 90s grace so a healthy app can reconnect and resume
            // heartbeating after a daemon restart; a dead app won't, and the
            // watchdog clears the flag on the first stale tick.
            lastHeartbeat = Date()
            log.info("adopted running flag at startup; keep awake until app reconnects")
        }
        startWatchdog()
    }


    func setKeepAwake(_ enabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        stateQueue.async { [self] in
            let outcome = Self.runPmset(disableSleep: enabled)
            if outcome.succeeded {
                lastHeartbeat = Date()
                log.info("set disablesleep=\(enabled ? "1" : "0") ok")
            } else {
                let detail = outcome.stderr.isEmpty
                    ? "pmset exited \(outcome.status)"
                    : outcome.stderr
                log.error("set disablesleep=\(enabled ? "1" : "0") failed: \(detail)")
                reply(false, detail)
                return
            }
            reply(true, nil)
        }
    }

    func heartbeat(withReply reply: @escaping (Bool) -> Void) {
        stateQueue.async { [self] in
            lastHeartbeat = Date()
            reply(true)
        }
    }

    func version(withReply reply: @escaping (String) -> Void) {
        reply(Self.versionString)
    }


    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(
            deadline: .now() + CapsAwakeDefaults.watchdogTickInterval,
            repeating: CapsAwakeDefaults.watchdogTickInterval
        )
        timer.setEventHandler { [weak self] in
            self?.watchdogTick()
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func watchdogTick() {
        let flagOn = Self.currentFlagIsEnabled()
        let heartbeatAge = Date().timeIntervalSince(lastHeartbeat)
        switch WatchdogPolicy.decide(
            flagEnabled: flagOn,
            heartbeatAge: heartbeatAge,
            timeout: CapsAwakeDefaults.watchdogTimeout
        ) {
        case .idle:
            break
        case .keep:
            break
        case .restore:
            log.warning("watchdog restoring sleep: no heartbeat for \(heartbeatAge)s")
            _ = Self.runPmset(disableSleep: false)
        }
    }


    @discardableResult
    private static func runPmset(disableSleep: Bool) -> CommandOutcome {
        ProcessRunner.run(
            "/usr/bin/pmset",
            ["-a", "disablesleep", disableSleep ? "1" : "0"]
        )
    }

    private static func currentFlagIsEnabled() -> Bool {
        let outcome = ProcessRunner.run("/usr/bin/pmset", ["-g"])
        return PmsetParsing.resolveFlag(status: outcome.status, stdout: outcome.stdout) == .enabled
    }
}
