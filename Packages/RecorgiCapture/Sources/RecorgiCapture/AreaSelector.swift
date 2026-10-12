import AppKit
import RecorgiCore

@MainActor
public final class AreaSelector {
    public init() {}

    /// Shows the drag-to-select overlay on EVERY given display at once — like
    /// the system screenshot tool (⌘⇧5) — so the user just moves the cursor
    /// to whichever monitor they want and drags there directly, with no
    /// separate "pick a display first" step. Returns which display the user
    /// actually dragged on plus the chosen rect, or nil if they cancelled
    /// (Escape, or too small a drag, on whichever screen they interacted
    /// with).
    ///
    /// The returned rect is in the coordinate space `SCStreamConfiguration
    /// .sourceRect` expects: local to that display, top-left origin, points
    /// (not pixels) — converted here from AppKit's bottom-left-origin view
    /// coordinates.
    public func selectArea(on displays: [DisplayInfo]) async -> (DisplayInfo, CGRect)? {
        let pairs: [(display: DisplayInfo, screen: NSScreen)] = displays.compactMap { display in
            guard let screen = NSScreen.screens.first(where: { Self.displayID(for: $0) == display.displayID }) else {
                Log.capture.error("AreaSelector: no NSScreen found for displayID=\(display.displayID, privacy: .public)")
                return nil
            }
            return (display, screen)
        }
        guard !pairs.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            var windows: [AreaSelectionWindow] = []
            var didResolve = false

            for pair in pairs {
                let display = pair.display
                let screen = pair.screen
                let overlay = AreaSelectionWindow(screen: screen) { viewRect in
                    guard !didResolve else { return }
                    didResolve = true
                    // Only one screen's answer matters — hide every other
                    // overlay the instant this one finishes (drag or Escape).
                    windows.forEach { $0.cancelWithoutCompletion() }

                    guard let viewRect else {
                        continuation.resume(returning: nil)
                        return
                    }
                    // AppKit view coordinates are bottom-left origin;
                    // sourceRect wants top-left origin, matching
                    // CoreGraphics display conventions.
                    let flippedY = screen.frame.height - viewRect.maxY
                    let rect = CGRect(x: viewRect.minX, y: flippedY, width: viewRect.width, height: viewRect.height)
                    continuation.resume(returning: (display, rect))
                }
                windows.append(overlay)
            }

            windows.forEach { $0.beginSelection() }
        }
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
