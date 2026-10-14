import ScreenCaptureKit
import AppKit
import RecorgiCore

/// Captures small live screenshots of displays/windows for the capture-
/// region picker's previews, so picking a source shows what's actually on
/// it instead of a generic icon. Not cached — screen content changes —
/// callers simply reload when the picker appears; SCDisplay/SCWindow stay
/// fully internal here, matching CaptureSourceProvider's existing
/// not-Sendable-across-the-boundary discipline.
public struct CaptureThumbnailLoader: Sendable {
    public init() {}

    public func thumbnail(forDisplay displayID: UInt32, maxDimension: CGFloat = 320) async -> NSImage? {
        await ThumbnailLoadGate.shared.acquire()
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            await ThumbnailLoadGate.shared.release()
            return nil
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let size = Self.fittedSize(width: display.width, height: display.height, maxDimension: maxDimension)
        let image = await capture(filter: filter, size: size)
        await ThumbnailLoadGate.shared.release()
        return image
    }

    public func thumbnail(forWindow windowID: UInt32, maxDimension: CGFloat = 320) async -> NSImage? {
        await ThumbnailLoadGate.shared.acquire()
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == windowID }) else {
            await ThumbnailLoadGate.shared.release()
            return nil
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let size = Self.fittedSize(width: Int(window.frame.width), height: Int(window.frame.height), maxDimension: maxDimension)
        let image = await capture(filter: filter, size: size)
        await ThumbnailLoadGate.shared.release()
        return image
    }

    private func capture(filter: SCContentFilter, size: (width: Int, height: Int)) async -> NSImage? {
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.width = max(size.width, 2)
        config.height = max(size.height, 2)
        config.scalesToFit = true
        guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
            Log.devices.debug("CaptureThumbnailLoader: captureImage failed")
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

/// Bounds how many thumbnail loads run at once. The capture-region picker
/// mounts one `SourceThumbnailView` per display/window all at once, and
/// each independently fires a full `SCShareableContent` window-server scan
/// plus a `captureImage` call — a burst of a dozen-plus of those landing on
/// ScreenCaptureKit at the very same moment is almost certainly why
/// thumbnails sat on their loading spinner indefinitely instead of
/// resolving. A plain async semaphore fixes that without ever touching
/// `SCShareableContent` itself inside the gate (it isn't `Sendable`, so it
/// can't be cached/shared across a `Task` boundary under strict
/// concurrency anyway — this only manages a counter and continuations,
/// both of which are fine to pass around).
private actor ThumbnailLoadGate {
    static let shared = ThumbnailLoadGate(limit: 3)

    private let limit: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
        self.available = limit
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            // Hand the freed slot straight to the next waiter instead of
            // incrementing `available` — avoids a window where a third
            // caller could grab the slot ahead of whoever's been queued
            // longest.
            waiters.removeFirst().resume()
        }
    }
}
