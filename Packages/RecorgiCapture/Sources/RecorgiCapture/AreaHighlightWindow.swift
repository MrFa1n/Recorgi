import AppKit

/// A thin, click-through border drawn around a chosen area — a persistent
/// visual reminder of exactly what's being captured, both while configuring
/// it and while actually recording. Unlike AreaSelectionWindow, this one
/// doesn't dim the rest of the screen or accept any input.
final class AreaHighlightWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hasShadow = false
        contentView = AreaHighlightView(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    func update(rect: CGRect) {
        (contentView as? AreaHighlightView)?.highlightRect = rect
    }
}

private final class AreaHighlightView: NSView {
    var highlightRect: CGRect = .zero {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard highlightRect != .zero else { return }
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: highlightRect.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 3
        path.stroke()
    }
}

/// Owns one highlight window's lifecycle. Safe to call show/hide repeatedly.
@MainActor
public final class AreaHighlighter {
    private var window: AreaHighlightWindow?

    public init() {}

    /// The highlight window's own CGWindowID, for callers that need to
    /// exclude it from a capture (so the border itself never ends up baked
    /// into the recording).
    public var highlightedWindowID: UInt32? {
        guard let window, window.windowNumber >= 0 else { return nil }
        return UInt32(window.windowNumber)
    }

    public func show(on displayID: UInt32, rect: CGRect) {
        guard let screen = NSScreen.screens.first(where: { Self.displayID(for: $0) == displayID }) else {
            hide()
            return
        }
        let win = window ?? AreaHighlightWindow(screen: screen)
        window = win
        // AppKit's bottom-left origin vs the top-left origin `rect` is
        // stored in (SCStreamConfiguration.sourceRect convention) — the same
        // flip AreaSelector applies, just inverted back.
        let flipped = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
        win.update(rect: flipped)
        win.orderFrontRegardless()
    }

    public func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
