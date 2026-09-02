import Foundation

/// Identities shared by the app and its privileged helper. The helper label,
/// Mach service name, LaunchDaemon plist basename and code-signing requirement
/// are all derived from the app's bundle id at runtime, so a build with a
/// different bundle id (e.g. a local `.dev` copy) registers a fully isolated
/// daemon and never collides with an installed release.
public enum CapsAwakeIdentity {
    public static let appBundleID = "com.piszeprogramy.capsawake"

    /// Env var the generated LaunchDaemon plist passes to the bundle-less
    /// helper executable so it knows which Mach service to listen on.
    public static let helperLabelEnvKey = "CAPSAWAKE_MACH_LABEL"

    /// Team ID (certificate OU) of the certificate that signs the app. Must
    /// equal the OU of the signing identity used by `scripts/build-app.sh`, or
    /// the helper rejects every incoming connection (helper-side code-signing
    /// check). `codesign -dv` reports this as TeamIdentifier.
    public static let teamID = "3UKH2QRFKZ"

    public static func helperLabel(appBundleID: String) -> String {
        "\(appBundleID).helper"
    }

    public static func helperBundleID(appBundleID: String) -> String {
        helperLabel(appBundleID: appBundleID)
    }

    public static func appBundleID(fromHelperLabel label: String) -> String? {
        let suffix = ".helper"
        guard label.hasSuffix(suffix), label.count > suffix.count else { return nil }
        return String(label.dropLast(suffix.count))
    }

    /// Requirement the helper demands of anything connecting to it. Every
    /// process on the machine can reach the Mach service a launchd daemon
    /// owns, so a plain listener would let any program ask a root process to
    /// hold the Mac awake. `identifier` alone would admit any binary claiming
    /// the name; `anchor apple generic` alone would admit every Apple-signed
    /// app; the OU check pins it to our team. Together: our app, signed by us.
    public static func codeSigningRequirement(appBundleID: String) -> String {
        "identifier \"\(appBundleID)\""
            + " and anchor apple generic"
            + " and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
