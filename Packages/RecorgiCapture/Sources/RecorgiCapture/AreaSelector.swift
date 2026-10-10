import AppKit

@MainActor
public final class AreaSelector {
    public init() {}

    /// Shows the drag-to-select overlay on the given display and returns the
    /// chosen rect, or nil if the user cancelled (Escape, or too small a drag).
    ///
    /// The returned rect is in the coordinate space `SCStreamConfiguration
    /// .sourceRect` expects: local to that display, top-left origin, points
    /// (not pixels) — converted here from AppKit's bottom-left-origin view
    /// coordinates.
    public func selectArea(on displayID: UInt32) async -> CGRect? {
        guard let screen = NSScreen.screens.first(where: { Self.displayID(for: $0) == displayID }) else {
            return nil
        }

        let viewRect: CGRect? = await withCheckedContinuation { continuation in
            let overlay = AreaSelectionWindow(screen: screen) { rect in
                continuation.resume(returning: rect)
            }
            overlay.beginSelection()
        }

        guard let viewRect else { return nil }

        // AppKit view coordinates are bottom-left origin; sourceRect wants
        // top-left origin, matching CoreGraphics display conventions.
        let flippedY = screen.frame.height - viewRect.maxY
        return CGRect(x: viewRect.minX, y: flippedY, width: viewRect.width, height: viewRect.height)
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
