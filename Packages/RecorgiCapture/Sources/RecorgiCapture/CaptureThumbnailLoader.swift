import ScreenCaptureKit
import AppKit

/// Captures small live screenshots of displays/windows for the capture-
/// region picker's previews, so picking a source shows what's actually on
/// it instead of a generic icon. Not cached — screen content changes —
/// callers simply reload when the picker appears; SCDisplay/SCWindow stay
/// fully internal here, matching CaptureSourceProvider's existing
/// not-Sendable-across-the-boundary discipline.
public struct CaptureThumbnailLoader: Sendable {
    public init() {}

    public func thumbnail(forDisplay displayID: UInt32, maxDimension: CGFloat = 320) async -> NSImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            return nil
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let size = Self.fittedSize(width: display.width, height: display.height, maxDimension: maxDimension)
        return await capture(filter: filter, size: size)
    }

    public func thumbnail(forWindow windowID: UInt32, maxDimension: CGFloat = 320) async -> NSImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == windowID }) else {
            return nil
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let size = Self.fittedSize(width: Int(window.frame.width), height: Int(window.frame.height), maxDimension: maxDimension)
        return await capture(filter: filter, size: size)
    }

    private func capture(filter: SCContentFilter, size: (width: Int, height: Int)) async -> NSImage? {
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.width = max(size.width, 2)
        config.height = max(size.height, 2)
        config.scalesToFit = true
        guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func fittedSize(width: Int, height: Int, maxDimension: CGFloat) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else {
            return (Int(maxDimension), Int(maxDimension * 9 / 16))
        }
        let aspect = CGFloat(width) / CGFloat(height)
        if aspect >= 1 {
            return (Int(maxDimension), Int(maxDimension / aspect))
        } else {
            return (Int(maxDimension * aspect), Int(maxDimension))
        }
    }
}
