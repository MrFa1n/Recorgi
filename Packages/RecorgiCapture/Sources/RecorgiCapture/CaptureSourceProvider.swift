import ScreenCaptureKit
import AppKit
import RecorgiCore

public struct CaptureSourceProvider: Sendable {
    public init() {}

    public func availableDisplays() async throws -> [DisplayInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        // Extract plain values first — SCDisplay itself isn't Sendable, so
        // it can't cross into the MainActor.run closure below, only these
        // primitives can.
        let raw = content.displays.map { (id: $0.displayID, width: $0.width, height: $0.height) }
        return await MainActor.run {
            raw.map { entry in
                DisplayInfo(
                    displayID: entry.id,
                    name: Self.systemDisplayName(for: entry.id),
                    width: entry.width,
                    height: entry.height
                )
            }
        }
    }

    /// The same name System Settings shows ("Built-in Display", "Studio
    /// Display", …) — NSScreen is the only place that's exposed; SCDisplay
    /// itself has no name property.
    @MainActor
    private static func systemDisplayName(for displayID: UInt32) -> String {
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               number.uint32Value == displayID {
                return screen.localizedName
            }
        }
        return "Дисплей"
    }

    public func availableWindows() async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.windows
            .filter { window in
                window.isOnScreen && window.windowLayer == 0 && !(window.title ?? "").isEmpty
            }
            .map { window in
                WindowInfo(
                    windowID: window.windowID,
                    title: window.title ?? "",
                    appName: window.owningApplication?.applicationName ?? "",
                    width: Int(window.frame.width),
                    height: Int(window.frame.height)
                )
            }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }
}
