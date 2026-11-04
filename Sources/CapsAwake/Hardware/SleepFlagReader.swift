import Foundation
import IOKit
import CapsAwakeShared

/// Unprivileged read of the system `SleepDisabled` flag via IOKit (`IOPMrootDomain`)
/// with a `pmset -g` fallback.
///
/// Reading via IOKit is in-process, non-blocking, and spawns zero subprocesses
/// or pipes. The app never asks the helper to *read* state — reading needs no
/// privileges, and doing it locally keeps a dead/unapproved helper from
/// collapsing an unreadable state into a misleading "off".
enum SleepFlagReader {
    static func currentState() -> SleepDisabledState {
        if let iokitState = readViaIOKit() {
            return iokitState
        }
        let outcome = ProcessRunner.run("/usr/bin/pmset", ["-g"])
        return PmsetParsing.resolveFlag(status: outcome.status, stdout: outcome.stdout)
    }

    private static func readViaIOKit() -> SleepDisabledState? {
        let rootDomain = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard rootDomain != 0 else { return nil }
        defer { IOObjectRelease(rootDomain) }

        guard let prop = IORegistryEntryCreateCFProperty(
            rootDomain,
            "SleepDisabled" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            // Modern macOS omits the key until it has been set at least once;
            // verify the entry itself is readable by checking SystemPowerProfile
            // or SleepSupported before concluding disabled.
            if let dict = readRootDomainProperties(rootDomain) {
                if let val = dict["SleepDisabled"] as? Bool {
                    return val ? .enabled : .disabled
                }
                if let num = dict["SleepDisabled"] as? NSNumber {
                    return num.intValue != 0 ? .enabled : .disabled
                }
                return .disabled
            }
            return nil
        }

        if let boolVal = prop as? Bool {
            return boolVal ? .enabled : .disabled
        }
        if let numVal = prop as? NSNumber {
            return numVal.intValue != 0 ? .enabled : .disabled
        }
        return nil
    }

    private static func readRootDomainProperties(_ entry: io_registry_entry_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry,
            &props,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
        let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dict
    }
}
