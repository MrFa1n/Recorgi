import AppKit

/// A border drawn around a chosen area — a persistent visual reminder of
/// exactly what's being captured, both while configuring it and while
/// actually recording. While configuring (isInteractive == true), it's
/// directly draggable (move the body) and resizable (drag one of 8
/// handles), the same refinement interaction as the system screenshot
/// tool's area selection. During actual recording it stays click-through,
/// same as before — ScreenRecordingEngine's own instance never turns
/// interactivity on.
///
/// The window's frame is always sized to exactly the selection plus a
/// small margin for the handles — *not* the whole screen. A full-screen
/// window with ignoresMouseEvents turned off would swallow every click
/// anywhere on the display, not just over the selection: hitTest only
/// decides which view *within* a window handles an event, it doesn't make
/// clicks fall through to whatever's behind the window. Keeping the
/// window itself small is what actually makes everything outside the
/// selection clickable again.
final class AreaHighlightWindow: NSWindow {
    private let highlightView: AreaHighlightView
    private let margin: CGFloat = 12

    var onRectChange: ((CGRect) -> Void)?

    init() {
        let view = AreaHighlightView()
        self.highlightView = view
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hasShadow = false
        contentView = view
        view.margin = margin

        // Fired by the view during a drag, in global screen coordinates.
        // Owning the actual window-repositioning here (rather than in the
        // view) keeps the view from needing to know it's inside a window
        // that's constantly resizing itself to track the selection.
        view.onDrag = { [weak self] newRect in
            guard let self else { return }
            highlightView.selectionRect = newRect
            setFrame(newRect.insetBy(dx: -margin, dy: -margin), display: true)
            onRectChange?(newRect)
        }
    }

    /// Both rects are in AppKit global screen coordinates (bottom-left
    /// origin, offset for the display's own position on a multi-monitor
    /// setup) — the caller (AreaHighlighter) converts to/from the
    /// display-local, top-left-origin convention the rest of the app uses.
    func update(selectionRect: CGRect, displayBounds: CGRect) {
        highlightView.displayBounds = displayBounds
        highlightView.selectionRect = selectionRect
        setFrame(selectionRect.insetBy(dx: -margin, dy: -margin), display: true)
    }

    var isInteractive: Bool {
        get { !ignoresMouseEvents }
        set {
            ignoresMouseEvents = !newValue
            highlightView.isInteractive = newValue
        }
    }
}

private final class AreaHighlightView: NSView {
    var margin: CGFloat = 12
    var selectionRect: CGRect = .zero {
        didSet { needsDisplay = true }
    }
    var displayBounds: CGRect = .zero
    var isInteractive = false {
        didSet { updateTrackingAreas() }
    }
    /// Reports the proposed new selection rect (global screen coordinates)
    /// continuously while dragging.
    var onDrag: ((CGRect) -> Void)?

    private enum Handle: CaseIterable, Equatable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum DragMode {
        case move(startMouseGlobal: NSPoint, startRect: CGRect)
        case resize(handle: Handle, startMouseGlobal: NSPoint, startRect: CGRect)
    }

    private var dragMode: DragMode?
    private let handleSize: CGFloat = 10
    private let minimumSize: CGFloat = 40

    init() {
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // The window is always sized to exactly selectionRect + margin (see
    // AreaHighlightWindow), so within this view the border sits at a fixed
    // (margin, margin) offset regardless of where the window actually is
    // on screen.
    private var localHighlightRect: NSRect {
        NSRect(x: margin, y: margin, width: selectionRect.width, height: selectionRect.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard selectionRect.width > 0, selectionRect.height > 0 else { return }
        let rect = localHighlightRect
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 3
        path.stroke()

        guard isInteractive else { return }
        for handle in Handle.allCases {
            let oval = NSBezierPath(ovalIn: handleRect(for: handle, in: rect))
            NSColor.controlAccentColor.setFill()
            oval.fill()
            NSColor.white.setStroke()
            oval.lineWidth = 1.5
            oval.stroke()
        }
    }

    // Since the window is already cropped to the interactive zone, every
    // point inside this view counts.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive else { return nil }
        return bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        guard isInteractive else { return }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
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
        let globalMouse = NSEvent.mouseLocation
        if let handle = handle(at: point) {
            dragMode = .resize(handle: handle, startMouseGlobal: globalMouse, startRect: selectionRect)
        } else if localHighlightRect.contains(point) {
            dragMode = .move(startMouseGlobal: globalMouse, startRect: selectionRect)
        } else {
            dragMode = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragMode else { return }
        // Tracked in global screen coordinates, not view-local ones — the
        // window (and so this view's own coordinate space) moves and
        // resizes *during* the drag, which would make a view-local
        // reference point a moving target.
        let globalMouse = NSEvent.mouseLocation
        let bounds = displayBounds.width > 0 ? displayBounds : selectionRect.insetBy(dx: -100_000, dy: -100_000)

        let newRect: CGRect
        switch dragMode {
        case .move(let startMouseGlobal, let startRect):
            var origin = CGPoint(
                x: startRect.minX + (globalMouse.x - startMouseGlobal.x),
                y: startRect.minY + (globalMouse.y - startMouseGlobal.y)
            )
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - startRect.width)
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - startRect.height)
            newRect = CGRect(origin: origin, size: startRect.size)

        case .resize(let handle, let startMouseGlobal, let startRect):
            newRect = Self.resized(
                startRect,
                handle: handle,
                dx: globalMouse.x - startMouseGlobal.x,
                dy: globalMouse.y - startMouseGlobal.y,
                bounds: bounds,
                minimumSize: minimumSize
            )
        }

        onDrag?(newRect)
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = nil
    }

    private func handleRect(for handle: Handle, in rect: CGRect) -> NSRect {
        let center = position(of: handle, in: rect)
        return NSRect(x: center.x - handleSize / 2, y: center.y - handleSize / 2, width: handleSize, height: handleSize)
    }

    private func handle(at point: NSPoint) -> Handle? {
        let rect = localHighlightRect
        return Handle.allCases.first { handleRect(for: $0, in: rect).insetBy(dx: -handleSize / 2, dy: -handleSize / 2).contains(point) }
    }

    private func cursor(at point: NSPoint) -> NSCursor {
        guard let handle = handle(at: point) else {
            return localHighlightRect.contains(point) ? .openHand : .arrow
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

    /// Called with the new rect (top-left origin, relative to the display,
    /// matching the convention `show(on:rect:)` takes) whenever the user
    /// drags the border's body or a resize handle — only fires when
    /// `setInteractive(true)` was called.
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
        let win = window ?? AreaHighlightWindow()
        window = win
        win.isInteractive = interactive
        win.onRectChange = { [weak self] globalRect in
            guard let self else { return }
            self.onRectChange?(Self.localRect(fromGlobal: globalRect, screen: screen))
        }
        win.update(selectionRect: Self.globalRect(fromLocal: rect, screen: screen), displayBounds: screen.frame)
        win.orderFrontRegardless()
    }

    public func hide() {
        window?.orderOut(nil)
        window = nil
    }

    /// `rect` is top-left-origin, relative to the display's own frame
    /// (SCStreamConfiguration.sourceRect convention) — converts to AppKit
    /// global screen coordinates (bottom-left origin, offset by the
    /// screen's own position so this is correct on a multi-monitor setup
    /// too, not just the main display).
    private static func globalRect(fromLocal rect: CGRect, screen: NSScreen) -> CGRect {
        CGRect(
            x: screen.frame.origin.x + rect.minX,
            y: screen.frame.origin.y + (screen.frame.height - rect.maxY),
            width: rect.width,
            height: rect.height
        )
    }

    private static func localRect(fromGlobal rect: CGRect, screen: NSScreen) -> CGRect {
        CGRect(
            x: rect.minX - screen.frame.origin.x,
            y: screen.frame.height - (rect.minY - screen.frame.origin.y) - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
