import Foundation
import CapsAwakeShared

// The daemon plist passes the Mach service name through the environment, so
// one binary can serve any app bundle id that ships it.
let machLabel = ProcessInfo.processInfo.environment[CapsAwakeIdentity.helperLabelEnvKey]
    ?? CapsAwakeIdentity.helperLabel(appBundleID: CapsAwakeIdentity.appBundleID)

let delegate = HelperListenerDelegate(machLabel: machLabel)
let listener = NSXPCListener(machServiceName: machLabel)
listener.delegate = delegate
listener.resume()

RunLoop.current.run()
