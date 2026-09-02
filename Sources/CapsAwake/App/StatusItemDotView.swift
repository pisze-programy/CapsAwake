import AppKit


final class StatusItemDotView: NSView {
    var onRightClick: ((NSEvent) -> Void)?

    var color: NSColor = Config.dotOff {
        didSet {
            if oldValue != color {
                needsDisplay = true
            }
        }
    }

    private let dotDiameter: CGFloat = 12

    override var intrinsicContentSize: NSSize {
        NSSize(width: 24, height: NSStatusBar.system.thickness)
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = dotDiameter
        let rect = NSRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
        let path = NSBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()

        // A faint ring keeps the grey (off) dot visible against any menu bar
        // appearance without needing a template image.
        if color == Config.dotOff {
            NSColor.black.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    /// Left click is intentionally inert — the only UI is the status dot and
    /// the Quit menu on right-click.
    override func mouseDown(with event: NSEvent) {}

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}
