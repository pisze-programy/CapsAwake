import Foundation

/// Fixed, no-UI safety policy so an unattended Mac with `SleepDisabled` on
/// cannot cook itself in a bag or run the battery flat. The engine applies
/// this on top of the Caps Lock switch; there is no settings UI.
public enum SafetyPolicy {
    /// True when conditions are dangerous enough to force sleep back on,
    /// regardless of Caps Lock. Critical thermal pressure, or a nearly empty
    /// battery while unplugged.
    public static func shouldForceSleep(
        batteryPercent: Int,
        onAC: Bool,
        thermalState: ProcessInfo.ThermalState,
        lowBatteryPercent: Int = CapsAwakeDefaults.lowBatteryPercent
    ) -> Bool {
        thermalState == .critical || (!onAC && batteryPercent <= lowBatteryPercent)
    }

    /// True once conditions are safe again (so the engine may re-apply the
    /// user's Caps Lock intent instead of staying force-restored forever).
    public static func conditionsCleared(
        batteryPercent: Int,
        onAC: Bool,
        thermalState: ProcessInfo.ThermalState,
        lowBatteryPercent: Int = CapsAwakeDefaults.lowBatteryPercent
    ) -> Bool {
        thermalState != .critical && (onAC || batteryPercent > lowBatteryPercent)
    }
}
