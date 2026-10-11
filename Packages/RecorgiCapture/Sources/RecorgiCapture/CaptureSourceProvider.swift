import ScreenCaptureKit
import AppKit
import RecorgiCore

public struct CaptureSourceProvider: Sendable {
    public init() {}

    public func availableDisplays() async throws -> [DisplayInfo] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            Log.devices.error("availableDisplays(): SCShareableContent fetch failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        // Extract plain values first — SCDisplay itself isn't Sendable, so
        // it can't cross into the MainActor.run closure below, only these
        // primitives can.
        let raw = content.displays.map { (id: $0.displayID, width: $0.width, height: $0.height) }
        let result = await MainActor.run {
            raw.map { entry in
                DisplayInfo(
                    displayID: entry.id,
                    name: Self.systemDisplayName(for: entry.id),
                    width: entry.width,
                    height: entry.height
                )
            }
        }
        Log.devices.debug("availableDisplays(): found \(result.count, privacy: .public)")
        return result
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
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            Log.devices.error("availableWindows(): SCShareableContent fetch failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let windows = content.windows
            .filter { window in
                window.isOnScreen && window.windowLayer == 0 && !(window.title ?? "").isEmpty
            }
            .map { window in
                WindowInfo(
                    windowID: window.windowID,
                    title: window.title ?? "",
                    appName: window.owningApplication?.applicationName ?? "",
                    processID: window.owningApplication?.processID ?? 0,
                    width: Int(window.frame.width),
                    height: Int(window.frame.height)
                )
            }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        Log.devices.debug("availableWindows(): found \(windows.count, privacy: .public)")
        return windows
    }
}
