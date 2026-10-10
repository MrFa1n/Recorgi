import AppKit

/// A border drawn around a chosen area — a persistent visual reminder of
/// exactly what's being captured, both while configuring it and while
/// actually recording. While configuring (isInteractive == true), it's
/// directly draggable (move the body) and resizable (drag one of 8
/// handles), the same refinement interaction as the system screenshot
/// tool's area selection. During actual recording it stays click-through,
/// same as before — ScreenRecordingEngine's own instance never turns
/// interactivity on.
final class AreaHighlightWindow: NSWindow {
    private let highlightView: AreaHighlightView

    init(screen: NSScreen) {
        let view = AreaHighlightView(frame: NSRect(origin: .zero, size: screen.frame.size))
        self.highlightView = view
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hasShadow = false
        contentView = view
    }

    func update(rect: CGRect) {
        highlightView.highlightRect = rect
    }

    var isInteractive: Bool {
        get { !ignoresMouseEvents }
        set {
            ignoresMouseEvents = !newValue
            highlightView.isInteractive = newValue
        }
    }

    /// Reports the new rect, in the view's own local coordinate space
    /// (bottom-left origin) — same convention `highlightRect`/`update(rect:)`
    /// use. The caller (AreaHighlighter) converts back to top-left origin.
    var onRectChange: ((CGRect) -> Void)? {
        get { highlightView.onRectChange }
        set { highlightView.onRectChange = newValue }
    }
}

private final class AreaHighlightView: NSView {
    var highlightRect: CGRect = .zero {
        didSet {
            needsDisplay = true
            if oldValue.size != highlightRect.size || oldValue.origin != highlightRect.origin {
                updateTrackingAreas()
            }
        }
    }
    var isInteractive = false {
        didSet { updateTrackingAreas() }
    }
    var onRectChange: ((CGRect) -> Void)?

    private enum Handle: CaseIterable, Equatable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum DragMode {
        case move(startMouse: NSPoint, startRect: CGRect)
        case resize(handle: Handle, startMouse: NSPoint, startRect: CGRect)
    }

    private var dragMode: DragMode?
    private let handleSize: CGFloat = 10
    private let minimumSize: CGFloat = 40

    override func draw(_ dirtyRect: NSRect) {
        guard highlightRect != .zero else { return }
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: highlightRect.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 3
        path.stroke()

        guard isInteractive else { return }
        for handle in Handle.allCases {
            let rect = handleRect(for: handle)
            let oval = NSBezierPath(ovalIn: rect)
            NSColor.controlAccentColor.setFill()
            oval.fill()
            NSColor.white.setStroke()
            oval.lineWidth = 1.5
            oval.stroke()
        }
    }

    // Click-through everywhere except the interactive zone itself (the
    // rect plus a handle-sized margin) — otherwise, with ignoresMouseEvents
    // turned off to allow dragging, this full-screen window would swallow
    // every click anywhere on the display, not just over the selection.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive, highlightRect != .zero else { return nil }
        return highlightRect.insetBy(dx: -handleSize, dy: -handleSize).contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        guard isInteractive, highlightRect != .zero else { return }
        addTrackingArea(NSTrackingArea(
            rect: highlightRect.insetBy(dx: -handleSize, dy: -handleSize),
            options: [.activeAlways, .cursorUpdate, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    override func mouseMoved(with event: NSEvent) {
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let handle = handle(at: point) {
            dragMode = .resize(handle: handle, startMouse: point, startRect: highlightRect)
        } else if highlightRect.contains(point) {
            dragMode = .move(startMouse: point, startRect: highlightRect)
        } else {
            dragMode = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragMode else { return }
        let point = convert(event.locationInWindow, from: nil)

        switch dragMode {
        case .move(let startMouse, let startRect):
            var origin = CGPoint(x: startRect.minX + (point.x - startMouse.x), y: startRect.minY + (point.y - startMouse.y))
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - startRect.width)
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - startRect.height)
            highlightRect = CGRect(origin: origin, size: startRect.size)

        case .resize(let handle, let startMouse, let startRect):
            highlightRect = Self.resized(
                startRect,
                handle: handle,
                dx: point.x - startMouse.x,
                dy: point.y - startMouse.y,
                bounds: bounds,
                minimumSize: minimumSize
            )
        }

        onRectChange?(highlightRect)
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = nil
    }

    private func handleRect(for handle: Handle) -> NSRect {
        let center = position(of: handle, in: highlightRect)
        return NSRect(x: center.x - handleSize / 2, y: center.y - handleSize / 2, width: handleSize, height: handleSize)
    }

    private func handle(at point: NSPoint) -> Handle? {
        Handle.allCases.first { handleRect(for: $0).insetBy(dx: -handleSize / 2, dy: -handleSize / 2).contains(point) }
    }

    private func cursor(at point: NSPoint) -> NSCursor {
        guard let handle = handle(at: point) else {
            return highlightRect.contains(point) ? .openHand : .arrow
        }
        switch handle {
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        // AppKit has no public diagonal resize cursor; crosshair at least
        // reads as "this corner does something" rather than showing the
        // wrong directional cursor.
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return .crosshair
        }
    }

    private func position(of handle: Handle, in rect: CGRect) -> NSPoint {
        switch handle {
        case .topLeft: return NSPoint(x: rect.minX, y: rect.maxY)
        case .top: return NSPoint(x: rect.midX, y: rect.maxY)
        case .topRight: return NSPoint(x: rect.maxX, y: rect.maxY)
        case .right: return NSPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return NSPoint(x: rect.maxX, y: rect.minY)
        case .bottom: return NSPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: return NSPoint(x: rect.minX, y: rect.minY)
        case .left: return NSPoint(x: rect.minX, y: rect.midY)
        }
    }

    private static func resized(_ rect: CGRect, handle: Handle, dx: CGFloat, dy: CGFloat, bounds: CGRect, minimumSize: CGFloat) -> CGRect {
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY

        switch handle {
        case .topLeft: minX += dx; maxY += dy
        case .top: maxY += dy
        case .topRight: maxX += dx; maxY += dy
        case .right: maxX += dx
        case .bottomRight: maxX += dx; minY += dy
        case .bottom: minY += dy
        case .bottomLeft: minX += dx; minY += dy
        case .left: minX += dx
        }

        minX = max(minX, bounds.minX)
        minY = max(minY, bounds.minY)
        maxX = min(maxX, bounds.maxX)
        maxY = min(maxY, bounds.maxY)

        let leftHandles: Set<Handle> = [.topLeft, .left, .bottomLeft]
        let bottomHandles: Set<Handle> = [.bottomLeft, .bottom, .bottomRight]

        if maxX - minX < minimumSize {
            if leftHandles.contains(handle) { minX = maxX - minimumSize } else { maxX = minX + minimumSize }
        }
        if maxY - minY < minimumSize {
            if bottomHandles.contains(handle) { minY = maxY - minimumSize } else { maxY = minY + minimumSize }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Owns one highlight window's lifecycle. Safe to call show/hide repeatedly.
@MainActor
public final class AreaHighlighter {
    private var window: AreaHighlightWindow?
    private var interactive = false

    /// Called with the new rect (top-left origin, matching the convention
    /// `show(on:rect:)` takes) whenever the user drags the border's body or
    /// a resize handle — only fires when `setInteractive(true)` was called.
    public var onRectChange: ((CGRect) -> Void)?

    public init() {}

    /// The highlight window's own CGWindowID, for callers that need to
    /// exclude it from a capture (so the border itself never ends up baked
    /// into the recording).
    public var highlightedWindowID: UInt32? {
        guard let window, window.windowNumber >= 0 else { return nil }
        return UInt32(window.windowNumber)
    }

    /// Lets the user directly drag/resize the border before recording
    /// starts. Never call this on the instance ScreenRecordingEngine shows
    /// during an actual recording — that one must stay click-through.
    public func setInteractive(_ interactive: Bool) {
        self.interactive = interactive
        window?.isInteractive = interactive
    }

    public func show(on displayID: UInt32, rect: CGRect) {
        guard let screen = NSScreen.screens.first(where: { Self.displayID(for: $0) == displayID }) else {
            hide()
            return
        }
        let win = window ?? AreaHighlightWindow(screen: screen)
        window = win
        win.isInteractive = interactive
        win.onRectChange = { [weak self] flipped in
            guard let self else { return }
            let topLeft = CGRect(
                x: flipped.minX,
                y: screen.frame.height - flipped.maxY,
                width: flipped.width,
                height: flipped.height
            )
            self.onRectChange?(topLeft)
        }
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
