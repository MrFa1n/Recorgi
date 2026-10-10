import ScreenCaptureKit
import RecorgiCore

public struct CaptureSourceProvider: Sendable {
    public init() {}

    public func availableDisplays() async throws -> [DisplayInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.displays.enumerated().map { index, display in
            DisplayInfo(
                displayID: display.displayID,
                name: index == 0 ? "Основной дисплей" : "Дисплей \(index + 1)",
                width: display.width,
                height: display.height
            )
        }
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
