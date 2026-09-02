import AppKit

/// Presentation-level constants for the app (colors, labels, tooltips).
enum Config {
    static let appDisplayName = "CapsAwake"

    static let dotOff = NSColor(srgbRed: 0.42, green: 0.42, blue: 0.45, alpha: 1.0)
    static let dotOn = NSColor(srgbRed: 0x22 / 255.0, green: 0xC5 / 255.0, blue: 0x5E / 255.0, alpha: 1.0)
    static let dotError = NSColor.systemRed

    static let tooltipOff = "Caps Lock OFF — normal sleep"
    static let tooltipOn = "Caps Lock ON — sleep disabled, Mac stays awake"
    static let tooltipPending = "Applying…"
    static let tooltipUnavailable = "Helper unavailable — approve CapsAwake in System Settings → General → Login Items & Extensions"
    static let tooltipFailed = "CapsAwake could not change the sleep setting — retrying"
    static let tooltipSafety = "Auto-restored: battery too low or thermal pressure — turn Caps Lock off, then on to retry"

    static let quitTitle = "Quit CapsAwake"
}
