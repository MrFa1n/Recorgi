import AppKit

/// Full-screen transparent overlay that lets the user drag out a rectangle,
/// the same interaction as macOS's built-in screenshot tool (⌘⇧5)'s area
/// selection: drag to mark it, the dimmed-except-selection view holds in
/// place so you can actually see what you picked, Enter confirms, Escape
/// cancels. Reports the rect in the view's own local coordinate space
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
        acceptsMouseMovedEvents = true

        let view = AreaSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onComplete = { [weak self] rect in
            self?.finish(with: rect)
        }
        contentView = view
    }

    // Borderless windows return false for both by default, which silently
    // blocks all keyboard input (keyDown only ever reaches the key window) —
    // that's why Enter/Escape never did anything.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func beginSelection() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(contentView)
        // Set immediately — tracking-area cursorUpdate only fires once the
        // mouse actually moves, which leaves the old cursor showing if it's
        // already sitting still over the overlay when it appears.
        NSCursor.crosshair.set()
    }

    private func finish(with rect: CGRect?) {
        orderOut(nil)
        NSCursor.pop()
        completion(rect)
    }
}

private final class AreaSelectionView: NSView {
    var onComplete: ((CGRect?) -> Void)?
    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private var isConfirming = false

    private static let instructions = "Перетащи, чтобы выделить область  ·  Enter — подтвердить  ·  Esc — отмена"

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        setUpTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setUpTrackingArea()
    }

    private func setUpTrackingArea() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .cursorUpdate, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        isConfirming = false
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
            currentRect = nil
            needsDisplay = true
            return
        }
        // Hold the dimmed/hole view here instead of finishing immediately —
        // otherwise the overlay vanishes the instant you release the mouse
        // and there's no chance to actually see what got selected.
        isConfirming = true
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            onComplete?(nil)
        case 36, 76: // Return, Enter (numpad)
            if isConfirming, let rect = currentRect {
                onComplete?(rect)
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        if let rect = currentRect {
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

        drawInstructions()
    }

    private func drawInstructions() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let text = Self.instructions as NSString
        let textSize = text.size(withAttributes: attributes)
        let padding: CGFloat = 10
        let origin = NSPoint(x: (bounds.width - textSize.width) / 2, y: bounds.height - textSize.height - 32)
        let backgroundRect = NSRect(
            x: origin.x - padding,
            y: origin.y - padding / 2,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )

        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: backgroundRect, xRadius: 8, yRadius: 8).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
