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

    /// `.regular` is macOS's own definition of "a foreground app with a
    /// Dock icon and a menu bar" — exactly the set of apps someone would
    /// recognize and actually want to record, as opposed to background
    /// system helpers (WindowManager's Dock bounce/zoom animation plate,
    /// third-party uninstaller helpers, input-method agents, …) that can
    /// still own a layer-0 window with a real-looking title.
    @MainActor
    private static func regularAppPIDs(among pids: Set<pid_t>) -> Set<pid_t> {
        pids.filter { NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular }
    }

    public func availableWindows() async throws -> [WindowInfo] {
        let content: SCShareableContent
        do {
            // onScreenWindowsOnly: false, not true — true silently drops any
            // window that isn't on the *currently active* Space (macOS gives
            // each display/Space its own notion of "on screen" by default).
            // A user reported exactly this: real, open windows (Mail, VS
            // Code) missing from the picker just because another Space was
            // active at the time. SCContentFilter(desktopIndependentWindow:)
            // — what picking a window actually uses — is specifically built
            // to keep recording a window across Space switches, so there's
            // no reason the picker itself should be Space-restricted; the
            // layer/title filter below already does the real job of
            // excluding menu bar items, helper windows, and other junk.
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        } catch {
            Log.devices.error("availableWindows(): SCShareableContent fetch failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        // windowLayer/title alone isn't enough once off-Space windows are
        // allowed through (see above) — resolved once, for every distinct
        // owning app, rather than per window.
        let candidatePIDs = Set(content.windows.compactMap { $0.owningApplication?.processID })
        let regularPIDs = await Self.regularAppPIDs(among: candidatePIDs)

        let windows = content.windows
            .filter { window in
                guard window.windowLayer == 0, !(window.title ?? "").isEmpty,
                      let pid = window.owningApplication?.processID else { return false }
                return regularPIDs.contains(pid)
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
