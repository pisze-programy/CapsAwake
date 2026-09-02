import AppKit
import Foundation
import ServiceManagement
import CapsAwakeShared

/// Owns the connection to the privileged helper: registration state of the
/// `SMAppService` daemon, the update re-registration dance, and all XPC calls.
/// All completion handlers are delivered on the main queue.
final class HelperClient {
    private static let lastBuildKey = "LastRegisteredHelperBuild"

    private let defaults = UserDefaults.standard
    private var connection: NSXPCConnection?

    /// Derived from the app's bundle id so a `.dev` copy talks to its own
    /// daemon and never an installed release's.
    private var helperLabel: String {
        CapsAwakeIdentity.helperLabel(
            appBundleID: Bundle.main.bundleIdentifier ?? CapsAwakeIdentity.appBundleID
        )
    }

    private var plistName: String { "\(helperLabel).plist" }

    private var service: SMAppService {
        SMAppService.daemon(plistName: plistName)
    }

    var daemonStatus: SMAppService.Status { service.status }


    func registerDaemon() throws {
        try service.register()
    }

    func openSystemSettingsForApproval() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// After an app update the helper binary is re-signed and the existing
    /// launchd job holds a stale launch record; launchd then refuses to exec
    /// the new binary and XPC calls hang forever. Fix: when the build changed
    /// and the daemon looks enabled but does not answer, unregister and
    /// register fresh. Do not disturb healthy installs.
    func reconcileAfterInstallIfNeeded(completion: @escaping () -> Void) {
        let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard daemonStatus == .enabled,
              defaults.string(forKey: Self.lastBuildKey) != currentBuild else {
            defaults.set(currentBuild, forKey: Self.lastBuildKey)
            completion()
            return
        }

        checkReachable { reachable in
            if reachable {
                self.defaults.set(currentBuild, forKey: Self.lastBuildKey)
                completion()
                return
            }
            self.service.unregister { _ in
                // Give launchd/BTM a moment to drop the old job before re-adding.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    do { try self.service.register() } catch { /* surfaced by status later */ }
                    self.defaults.set(currentBuild, forKey: Self.lastBuildKey)
                    completion()
                }
            }
        }
    }


    private func connect() -> NSXPCConnection {
        if let existing = connection { return existing }
        let newConnection = NSXPCConnection(machServiceName: helperLabel, options: .privileged)
        newConnection.remoteObjectInterface = NSXPCInterface(with: KeepAwakeHelperProtocol.self)
        newConnection.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    private func proxy(_ onError: @escaping (String) -> Void) -> KeepAwakeHelperProtocol? {
        let remote = connect().remoteObjectProxyWithErrorHandler { error in
            DispatchQueue.main.async {
                onError(error.localizedDescription)
            }
        }
        return remote as? KeepAwakeHelperProtocol
    }

    func setKeepAwake(_ enabled: Bool, completion: @escaping (Bool, String?) -> Void) {
        callWithTimeout(completion: completion) { proxy, done in
            proxy.setKeepAwake(enabled) { ok, error in
                done(ok, error)
            }
        }
    }

    func heartbeat() {
        _ = proxy({ _ in })?.heartbeat { _ in }
    }

    /// True if the daemon answers an XPC call within the timeout; used both by
    /// the update re-registration dance and by the engine's degraded handling.
    func checkReachable(completion: @escaping (Bool) -> Void) {
        callWithTimeout(timeout: 5, completion: { ok, _ in completion(ok) }) { proxy, done in
            proxy.version { _ in done(true, nil) }
        }
    }

    /// Run one XPC call, guaranteeing `completion` fires exactly once on the
    /// main queue. If the daemon never replies (dead or stale after update),
    /// the timeout reports failure instead of leaving the engine hung.
    private func callWithTimeout(
        timeout: TimeInterval = CapsAwakeDefaults.xpcTimeout,
        completion: @escaping (Bool, String?) -> Void,
        _ body: (KeepAwakeHelperProtocol, @escaping (Bool, String?) -> Void) -> Void
    ) {
        var finished = false
        let finish: (Bool, String?) -> Void = { ok, error in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(ok, error)
            }
        }
        guard let proxy = proxy({ finish(false, $0) }) else {
            finish(false, "No helper connection")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            finish(false, "The background helper isn't responding.")
        }
        body(proxy) { ok, error in finish(ok, error) }
    }
}
