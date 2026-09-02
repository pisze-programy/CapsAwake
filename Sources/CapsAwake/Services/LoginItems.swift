import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService.mainApp`, enabled by default on first
/// launch. Auto-registration happens exactly once; after that the app never
/// touches the login item again, so a user disabling it in System Settings
/// actually sticks instead of being silently re-added on every launch.
enum LoginItemManager {
    private static let didAutoRegisterKey = "DidAutoRegisterLoginItemOnFirstLaunch"

    static func enableDefaultOnFirstLaunchIfApplicable() {
        guard isRunningFromApplications() else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didAutoRegisterKey) else { return }

        let status = SMAppService.mainApp.status
        if status == .enabled {
            defaults.set(true, forKey: didAutoRegisterKey)
            return
        }
        guard status == .notRegistered else {
            // requiresApproval etc. — never fought automatically.
            return
        }
        do {
            try SMAppService.mainApp.register()
            defaults.set(true, forKey: didAutoRegisterKey)
            AppLog.info("login item enabled")
        } catch {
            // Leave the flag unset so a later launch (e.g. after moving to
            // /Applications or signing) retries instead of giving up forever.
            AppLog.error("login item registration failed: \(error.localizedDescription)")
        }
    }

    /// `SMAppService` only works from an app in /Applications (or ~/Applications).
    /// A bare `swift run`/scratch build must never claim the one-time default.
    private static func isRunningFromApplications() -> Bool {
        let appPath = Bundle.main.bundleURL.standardizedFileURL.path
        let apps = [
            URL(fileURLWithPath: "/Applications").standardizedFileURL.path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications").standardizedFileURL.path
        ]
        return apps.contains { appPath.hasPrefix($0) }
    }
}
