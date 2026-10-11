import AppKit

private enum Handle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var cursor: NSCursor {
        switch self {
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        // AppKit has no public diagonal resize cursor; crosshair at least
        // reads as "this corner does something" rather than showing the
        // wrong directional cursor.
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return .crosshair
        }
    }

    func position(in rect: CGRect) -> NSPoint {
        switch self {
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
}

private enum Edge: CaseIterable {
    case top, bottom, left, right

    func frame(in rect: CGRect, handleSize: CGFloat, thickness: CGFloat) -> NSRect {
        switch self {
        case .top:
            return NSRect(x: rect.minX + handleSize / 2, y: rect.maxY - thickness / 2, width: max(0, rect.width - handleSize), height: thickness)
        case .bottom:
            return NSRect(x: rect.minX + handleSize / 2, y: rect.minY - thickness / 2, width: max(0, rect.width - handleSize), height: thickness)
        case .left:
            return NSRect(x: rect.minX - thickness / 2, y: rect.minY + handleSize / 2, width: thickness, height: max(0, rect.height - handleSize))
        case .right:
            return NSRect(x: rect.maxX - thickness / 2, y: rect.minY + handleSize / 2, width: thickness, height: max(0, rect.height - handleSize))
        }
    }
}

/// A tiny, precisely-sized window representing exactly one resize handle or
/// one draggable edge segment — never any bigger than that single hotspot.
///
/// This is the only way to get genuine click-through for everything else.
/// hitTest returning nil for a point still *inside* a window's frame does
/// NOT make the click fall through to the window behind — hitTest only
/// decides which view *within an already-claimed window* handles the
/// event. A single window covering the whole selection, even with
/// ignoresMouseEvents off only "logically" outside hitTest's claimed
/// region, still eats every click inside its frame — including, if the
/// selection happens to sit over this app's own window, its own buttons.
/// Many small windows, each exactly as big as the hotspot it represents,
/// is what actually leaves everything in between untouched.
private final class HotspotWindow: NSWindow {
    var onMouseDown: ((NSPoint) -> Void)?
    var onMouseDragged: ((NSPoint) -> Void)?
    var onMouseUp: (() -> Void)?

    init(cursor: NSCursor, drawsHandle: Bool) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hasShadow = false

        let view = HotspotView(cursor: cursor, drawsHandle: drawsHandle)
        view.onMouseDown = { [weak self] in self?.onMouseDown?(NSEvent.mouseLocation) }
        view.onMouseDragged = { [weak self] in self?.onMouseDragged?(NSEvent.mouseLocation) }
        view.onMouseUp = { [weak self] in self?.onMouseUp?() }
        contentView = view
    }

    func reposition(to frame: NSRect) {
        setFrame(frame, display: true)
    }

    var accentColor: NSColor {
        get { (contentView as? HotspotView)?.accentColor ?? .controlAccentColor }
        set { (contentView as? HotspotView)?.accentColor = newValue }
    }
}

private final class HotspotView: NSView {
    private let cursor: NSCursor
    private let drawsHandle: Bool
    var accentColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }
    var onMouseDown: (() -> Void)?
    var onMouseDragged: (() -> Void)?
    var onMouseUp: (() -> Void)?

    init(cursor: NSCursor, drawsHandle: Bool) {
        self.cursor = cursor
        self.drawsHandle = drawsHandle
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard drawsHandle else { return }
        let oval = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        accentColor.setFill()
        oval.fill()
        NSColor.white.setStroke()
        oval.lineWidth = 1.5
        oval.stroke()
    }

    // The whole window already *is* precisely this one hotspot, so the
    // view's entire bounds (not some sub-region) is the right zone — no
    // hitTest override needed here, unlike the old single-big-window design.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .cursorUpdate, .mouseMoved], owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseMoved(with event: NSEvent) { cursor.set() }
    override func mouseDown(with event: NSEvent) { onMouseDown?() }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?() }
    override func mouseUp(with event: NSEvent) { onMouseUp?() }
}

/// Purely visual — the accent-colored outline, always click-through. Used
/// both for the interactive (configuration-time) border and the plain one
/// shown during an actual recording.
private final class AreaBorderWindow: NSWindow {
    private let borderView = AreaBorderView()
    private let padding: CGFloat = 4

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hasShadow = false
        contentView = borderView
    }

    func update(rect: CGRect) {
        borderView.strokeRect = NSRect(x: padding, y: padding, width: rect.width, height: rect.height)
        setFrame(rect.insetBy(dx: -padding, dy: -padding), display: true)
    }

    var accentColor: NSColor {
        get { borderView.accentColor }
        set { borderView.accentColor = newValue }
    }
}

private final class AreaBorderView: NSView {
    var strokeRect: NSRect = .zero {
        didSet { needsDisplay = true }
    }
    var accentColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard strokeRect.width > 0, strokeRect.height > 0 else { return }
        accentColor.setStroke()
        let path = NSBezierPath(rect: strokeRect.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 3
        path.stroke()
    }
}

/// Owns the visual border plus, while interactive, the 8 handle + 4 edge
/// hotspot windows — shows/hides/repositions all of them together. Safe to
/// call show/hide repeatedly.
@MainActor
public final class AreaHighlighter {
    private let borderWindow = AreaBorderWindow()
    private var handleWindows: [Handle: HotspotWindow] = [:]
    private var edgeWindows: [Edge: HotspotWindow] = [:]

    private var interactiveFlag = false
    private var screen: NSScreen?
    private var selectionGlobal: CGRect = .zero
    private var displayBoundsGlobal: CGRect = .zero
    private var accentColor: NSColor = .controlAccentColor

    private let handleSize: CGFloat = 14
    private let edgeThickness: CGFloat = 12
    private let minimumSelectionSize: CGFloat = 40

    private struct DragState {
        let mouseStart: NSPoint
        let rectStart: CGRect
        let kind: Kind
        enum Kind {
            case move
            case resize(Handle)
        }
    }
    private var drag: DragState?

    /// Called with the new rect (top-left origin, relative to the display,
    /// matching the convention `show(on:rect:)` takes) whenever the user
    /// drags an edge or a resize handle — only fires when
    /// `setInteractive(true)` was called.
    public var onRectChange: ((CGRect) -> Void)?

    // In "follow the system" mode, setAccentColor stores the dynamic
    // .controlAccentColor constant itself, which *resolves* to the live
    // system accent at draw time — but these are plain custom NSViews, not
    // native AppKit controls, so nothing ever tells them *when* to redraw
    // after the user changes the system accent color in System Settings.
    // Native controls get that nudge automatically; a bare NSView.draw(_:)
    // doesn't, so without this observer the border/handles stay stuck with
    // whatever was on screen the last time something else (show/move)
    // happened to trigger a redraw.
    // nonisolated(unsafe): only ever written once in init and read once in
    // deinit (a nonisolated context even on a @MainActor class), never
    // mutated concurrently — NotificationCenter.removeObserver is itself
    // thread-safe to call with a stale/foreign token.
    nonisolated(unsafe) private var systemColorObserver: NSObjectProtocol?

    public init() {
        systemColorObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.redrawAllViews() }
        }
    }

    deinit {
        if let systemColorObserver {
            NotificationCenter.default.removeObserver(systemColorObserver)
        }
    }

    private func redrawAllViews() {
        borderWindow.contentView?.needsDisplay = true
        for window in handleWindows.values { window.contentView?.needsDisplay = true }
        for window in edgeWindows.values { window.contentView?.needsDisplay = true }
    }

    /// The border window's own CGWindowID, for callers that need to
    /// exclude it from a capture (so the border itself never ends up baked
    /// into the recording).
    public var highlightedWindowID: UInt32? {
        guard borderWindow.windowNumber >= 0 else { return nil }
        return UInt32(borderWindow.windowNumber)
    }

    /// Lets the user directly drag/resize the border before recording
    /// starts. Never call this on the instance ScreenRecordingEngine shows
    /// during an actual recording — that one must stay click-through.
    public func setInteractive(_ interactive: Bool) {
        interactiveFlag = interactive
        updateHotspotVisibility()
    }

    /// Defaults to .controlAccentColor (the system accent color, same as
    /// before this existed) — pass a specific color to theme the border and
    /// handles, or .controlAccentColor again to go back to following the
    /// system.
    public func setAccentColor(_ color: NSColor) {
        accentColor = color
        borderWindow.accentColor = color
        for window in handleWindows.values { window.accentColor = color }
        for window in edgeWindows.values { window.accentColor = color }
    }

    public func show(on displayID: UInt32, rect: CGRect) {
        guard let matchedScreen = NSScreen.screens.first(where: { Self.displayID(for: $0) == displayID }) else {
            hide()
            return
        }
        screen = matchedScreen
        displayBoundsGlobal = matchedScreen.frame
        selectionGlobal = Self.globalRect(fromLocal: rect, screen: matchedScreen)
        borderWindow.update(rect: selectionGlobal)
        borderWindow.orderFrontRegardless()
        updateHotspotVisibility()
    }

    public func hide() {
        borderWindow.orderOut(nil)
        for window in handleWindows.values { window.orderOut(nil) }
        for window in edgeWindows.values { window.orderOut(nil) }
        screen = nil
        drag = nil
    }

    private func updateHotspotVisibility() {
        guard interactiveFlag, screen != nil, selectionGlobal.width > 0 else {
            for window in handleWindows.values { window.orderOut(nil) }
            for window in edgeWindows.values { window.orderOut(nil) }
            return
        }
        ensureHotspotsExist()
        layoutHotspots()
        for window in handleWindows.values { window.orderFrontRegardless() }
        for window in edgeWindows.values { window.orderFrontRegardless() }
    }

    private func ensureHotspotsExist() {
        if handleWindows.isEmpty {
            for handle in Handle.allCases {
                let window = HotspotWindow(cursor: handle.cursor, drawsHandle: true)
                window.accentColor = accentColor
                window.onMouseDown = { [weak self] mouse in self?.beginDrag(.resize(handle), at: mouse) }
                window.onMouseDragged = { [weak self] mouse in self?.continueDrag(at: mouse) }
                window.onMouseUp = { [weak self] in self?.drag = nil }
                handleWindows[handle] = window
            }
        }
        if edgeWindows.isEmpty {
            for edge in Edge.allCases {
                let window = HotspotWindow(cursor: .openHand, drawsHandle: false)
                window.accentColor = accentColor
                window.onMouseDown = { [weak self] mouse in self?.beginDrag(.move, at: mouse) }
                window.onMouseDragged = { [weak self] mouse in self?.continueDrag(at: mouse) }
                window.onMouseUp = { [weak self] in self?.drag = nil }
                edgeWindows[edge] = window
            }
        }
    }

    private func layoutHotspots() {
        for (handle, window) in handleWindows {
            let center = handle.position(in: selectionGlobal)
            window.reposition(to: NSRect(x: center.x - handleSize / 2, y: center.y - handleSize / 2, width: handleSize, height: handleSize))
        }
        for (edge, window) in edgeWindows {
            window.reposition(to: edge.frame(in: selectionGlobal, handleSize: handleSize, thickness: edgeThickness))
        }
    }

    private func beginDrag(_ kind: DragState.Kind, at mouse: NSPoint) {
        drag = DragState(mouseStart: mouse, rectStart: selectionGlobal, kind: kind)
    }

    private func continueDrag(at mouse: NSPoint) {
        guard let drag else { return }
        let dx = mouse.x - drag.mouseStart.x
        let dy = mouse.y - drag.mouseStart.y
        let bounds = displayBoundsGlobal.width > 0 ? displayBoundsGlobal : drag.rectStart.insetBy(dx: -100_000, dy: -100_000)

        switch drag.kind {
        case .move:
            var origin = CGPoint(x: drag.rectStart.minX + dx, y: drag.rectStart.minY + dy)
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - drag.rectStart.width)
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - drag.rectStart.height)
            selectionGlobal = CGRect(origin: origin, size: drag.rectStart.size)
        case .resize(let handle):
            selectionGlobal = Self.resized(drag.rectStart, handle: handle, dx: dx, dy: dy, bounds: bounds, minimumSize: minimumSelectionSize)
        }

        borderWindow.update(rect: selectionGlobal)
        layoutHotspots()
        if let screen {
            onRectChange?(Self.localRect(fromGlobal: selectionGlobal, screen: screen))
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
