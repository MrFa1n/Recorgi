import AppKit

/// Full-screen transparent overlay that lets the user drag out a rectangle,
/// the same interaction as macOS's built-in screenshot tool (⌘⇧5)'s area
/// selection. Reports the rect in the view's own local coordinate space
/// (bottom-left origin) — the caller converts to whatever space it needs.
final class AreaSelectionWindow: NSWindow {
    private let completion: (CGRect?) -> Void

    init(screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hasShadow = false

        let view = AreaSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onComplete = { [weak self] rect in
            self?.finish(with: rect)
        }
        contentView = view
    }

    func beginSelection() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(contentView)
        if let contentView {
            invalidateCursorRects(for: contentView)
        }
    }

    private func finish(with rect: CGRect?) {
        orderOut(nil)
        completion(rect)
    }
}

private final class AreaSelectionView: NSView {
    var onComplete: ((CGRect?) -> Void)?
    private var startPoint: NSPoint?
    private var currentRect: NSRect?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        // Makes it obvious this overlay is in "drag to select" mode, same as
        // the system screenshot tool.
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { startPoint = nil }
        guard let rect = currentRect, rect.width > 4, rect.height > 4 else {
            onComplete?(nil)
            return
        }
        onComplete?(rect)
    }

    override func keyDown(with event: NSEvent) {
        // Escape cancels, matching the system screenshot tool.
        if event.keyCode == 53 {
            onComplete?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        guard let rect = currentRect else { return }

        // Punch the selected area back to clear so it reads as a "hole"
        // in the dim overlay, same as the system screenshot tool.
        NSGraphicsContext.current?.compositingOperation = .clear
        NSColor.clear.setFill()
        rect.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        NSColor.white.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
    }
}
