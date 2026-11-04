import AppKit
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import ServiceManagement
import CapsAwakeShared

final class CapsAwakeApp: NSObject, NSApplicationDelegate {
    private let capsProbe = CapsLockProbe()
    private let helperClient = HelperClient()
    private let statusDotView = StatusItemDotView()

    private var statusItem: NSStatusItem?
    private var engine: KeepAwakeEngine?
    private var pollTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    private var lastPresentedAlert: AlertReason?
    private var activeAlertWindow: NSWindow?

    /// IOKit power assertions held while Caps Lock is on to prevent display
    /// sleep, screensaver activation, and idle lock screen / session logout.
    private var displayAssertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var systemAssertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var userActivityAssertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var holdingSessionAssertions = false
    private var nextUserActivityAt = Date.distantPast

    /// When false (duplicate instance), termination must NOT issue "off" —
    /// that would kill the primary instance's keep-awake mid-session.
    private var shouldRestoreOnTerminate = true
    private var didShutdown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if terminateIfDuplicate() { return }

        NSApp.setActivationPolicy(.accessory)
        installStatusItem()

        LoginItemManager.enableDefaultOnFirstLaunchIfApplicable()

        let engine = KeepAwakeEngine(
            readCaps: { [weak self] in self?.capsProbe.isCapsLockOn() },
            readFlag: { SleepFlagReader.currentState() },
            safetySample: { Self.currentSafetySample() },
            client: helperClient,
            setSessionAwake: { [weak self] awake in self?.updateSessionAssertions(awake: awake) },
            onDisplay: { [weak self] display in self?.apply(display: display) }
        )
        self.engine = engine

        // After an app update the daemon may hold a stale launch record; repair
        // it once at launch so XPC does not hang forever.
        helperClient.reconcileAfterInstallIfNeeded {}

        let timer = Timer(timeInterval: CapsAwakeDefaults.capsLockPollInterval, repeats: true) { [weak self] _ in
            self?.engine?.poll()
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        RunLoop.main.add(timer, forMode: .eventTracking)
        pollTimer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(willPowerOff),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )

        installSignalHandlers()
        engine.poll()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        shutdownOnceIfNeeded()
        return .terminateNow
    }

    // MARK: Status bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 24)
        statusItem = item
        statusDotView.onRightClick = { [weak self] event in
            self?.showQuitMenu(triggering: event)
        }
        statusDotView.toolTip = Config.tooltipOff
        item.view = statusDotView
    }

    private func showQuitMenu(triggering event: NSEvent) {
        let menu = NSMenu()
        let quit = NSMenuItem(title: Config.quitTitle, action: #selector(requestQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: statusDotView)
    }

    @objc private func requestQuit() {
        NSApp.terminate(nil)
    }

    private func apply(display: DisplayState) {
        statusDotView.color = color(for: display.dot)
        statusDotView.toolTip = display.tooltip

        guard let reason = display.alert else {
            lastPresentedAlert = nil
            if let window = activeAlertWindow {
                activeAlertWindow = nil
                NSApp.abortModal()
                window.orderOut(nil)
            }
            return
        }
        guard reason != lastPresentedAlert else { return }
        lastPresentedAlert = reason
        AppLog.error("alert: \(String(describing: reason))")
        // Defer outside the current poll() tick so the engine finishes its
        // evaluation and heartbeat cycle before any UI work runs.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lastPresentedAlert == reason else { return }
            self.presentAlert(for: reason)
        }
    }

    private func presentAlert(for reason: AlertReason) {
        if let window = activeAlertWindow {
            activeAlertWindow = nil
            NSApp.abortModal()
            window.orderOut(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch reason {
        case .requiresApproval:
            alert.messageText = "CapsAwake helper needs approval"
            alert.informativeText = "Approve the helper in System Settings → General → Login Items & Extensions. Until then, Caps Lock cannot hold the Mac awake."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Dismiss")
        case .helperNotInstalled:
            alert.messageText = "CapsAwake helper is missing"
            alert.informativeText = "Reinstall the app with scripts/install.sh. The helper flips the system sleep flag as root."
            alert.addButton(withTitle: "Reveal Logs")
            alert.addButton(withTitle: "Dismiss")
        case .applyFailed:
            alert.messageText = "CapsAwake cannot change the sleep setting"
            alert.informativeText = "See the log for the reason. The app keeps retrying."
            alert.addButton(withTitle: "Reveal Logs")
            alert.addButton(withTitle: "Dismiss")
        case .safetyHold:
            alert.messageText = "CapsAwake turned itself off"
            alert.informativeText = "The battery is low or the Mac is hot. Turn Caps Lock off, then on, to retry."
            alert.addButton(withTitle: "OK")
        }

        activeAlertWindow = alert.window
        // Run the alert on the next run-loop turn; pollTimer is registered in
        // `.modalPanel` as well as `.common`, so polling and heartbeats continue
        // uninterrupted while the alert is visible.
        let response = alert.runModal()
        activeAlertWindow = nil
        if response == .alertFirstButtonReturn {
            switch reason {
            case .requiresApproval:
                helperClient.openSystemSettingsForApproval()
            case .helperNotInstalled, .applyFailed:
                NSWorkspace.shared.open(AppLog.logDirectoryURL)
            case .safetyHold:
                break
            }
        }
    }

    private func color(for dot: DotColor) -> NSColor {
        switch dot {
        case .off: return Config.dotOff
        case .on: return Config.dotOn
        case .error: return Config.dotError
        }
    }

    // MARK: Lifecycle helpers

    private func shutdownOnceIfNeeded() {
        guard shouldRestoreOnTerminate, !didShutdown else { return }
        didShutdown = true
        engine?.shutdownBlocking()
    }

    private func terminateIfDuplicate() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let selfPID = getpid()
        let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != selfPID && $0.processIdentifier > 0 && !$0.isTerminated }
        guard let first = existing.min(by: { $0.processIdentifier < $1.processIdentifier }) else {
            return false
        }
        shouldRestoreOnTerminate = false
        first.activate(options: [])
        NSApp.terminate(nil)
        return true
    }

    private func installSignalHandlers() {
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.shutdownOnceIfNeeded()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    @objc private func didWakeFromSleep() {
        engine?.wake()
    }

    @objc private func willPowerOff() {
        shutdownOnceIfNeeded()
    }

    // MARK: Session & display keep-awake assertions

    /// Holds IOKit display/idle assertions and periodically declares user
    /// activity while Caps Lock is active so macOS does not dim the display,
    /// start the screen saver, lock the session to loginwindow, or trigger
    /// inactivity auto-logout.
    private func updateSessionAssertions(awake: Bool) {
        let now = Date()
        if awake {
            if !holdingSessionAssertions {
                holdingSessionAssertions = true
                let reason = "CapsAwake — Caps Lock active" as CFString
                var dispID = IOPMAssertionID(kIOPMNullAssertionID)
                if IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    reason,
                    &dispID
                ) == kIOReturnSuccess {
                    displayAssertionID = dispID
                }
                var sysID = IOPMAssertionID(kIOPMNullAssertionID)
                if IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    reason,
                    &sysID
                ) == kIOReturnSuccess {
                    systemAssertionID = sysID
                }
                nextUserActivityAt = .distantPast
            }
            if now >= nextUserActivityAt {
                nextUserActivityAt = now + 30
                let reason = "CapsAwake — Caps Lock active" as CFString
                _ = IOPMAssertionDeclareUserActivity(
                    reason,
                    kIOPMUserActiveLocal,
                    &userActivityAssertionID
                )
            }
        } else if holdingSessionAssertions {
            holdingSessionAssertions = false
            if displayAssertionID != IOPMAssertionID(kIOPMNullAssertionID) {
                IOPMAssertionRelease(displayAssertionID)
                displayAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
            }
            if systemAssertionID != IOPMAssertionID(kIOPMNullAssertionID) {
                IOPMAssertionRelease(systemAssertionID)
                systemAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
            }
            if userActivityAssertionID != IOPMAssertionID(kIOPMNullAssertionID) {
                IOPMAssertionRelease(userActivityAssertionID)
                userActivityAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
            }
        }
    }

    // MARK: Safety inputs

    private static func currentSafetySample() -> SafetySample {
        if let iokitSample = readPowerSourceViaIOKit() {
            return iokitSample
        }
        let batt = ProcessRunner.run("/usr/bin/pmset", ["-g", "batt"]).stdout
        let percent = Self.parseBatteryPercent(batt) ?? 100
        let onAC = batt.localizedCaseInsensitiveContains("AC Power")
        return SafetySample(
            batteryPercent: percent,
            onAC: onAC,
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    private static func readPowerSourceViaIOKit() -> SafetySample? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        let providingType = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        var onAC = (providingType == (kIOPMACPowerKey as String))
        var percent: Int?

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let state = desc[kIOPSPowerSourceStateKey as String] as? String,
               state == (kIOPSACPowerValue as String) {
                onAC = true
            }
            if let cur = desc[kIOPSCurrentCapacityKey as String] as? Int,
               let max = desc[kIOPSMaxCapacityKey as String] as? Int,
               max > 0 {
                percent = Int((Double(cur) / Double(max) * 100.0).rounded())
            }
        }

        return SafetySample(
            batteryPercent: percent ?? 100,
            onAC: onAC,
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    private static func parseBatteryPercent(_ output: String) -> Int? {
        guard let range = output.range(of: #"\d+%"#, options: .regularExpression) else {
            return nil
        }
        let digits = output[range].dropLast()
        return Int(digits)
    }
}
