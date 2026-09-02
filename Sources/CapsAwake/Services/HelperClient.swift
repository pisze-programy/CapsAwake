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

    /// Full re-registration: unregister (boots the stale job) then register
    /// fresh. Needed after an app update or when the daemon reports enabled but
    /// no process answers — launchd holds a dead job and a plain register()
    /// does not clear it. Completion arrives on the main queue.
    func reregister(completion: @escaping () -> Void) {
        let daemon = service
        daemon.unregister { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                do {
                    try daemon.register()
                } catch {
                    // Survived by the engine's retry path; status will surface it.
                }
                completion()
            }
        }
    }

    /// Ensure the registered daemon actually answers. If it is enabled but the
    /// launchd job died (e.g. after an installer booted it out), re-register so
    /// a fresh helper starts.
    func reconcileAfterInstallIfNeeded(completion: @escaping () -> Void) {
        let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard daemonStatus == .enabled else {
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
            self.reregister {
                self.defaults.set(currentBuild, forKey: Self.lastBuildKey)
                completion()
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
