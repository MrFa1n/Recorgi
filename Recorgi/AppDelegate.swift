import AppKit
import RecorgiCore

/// Keeps Recorgi running (with its menu-bar item still live) after the main
/// window is closed, instead of the default SwiftUI behavior of quitting
/// once the last window goes away. Also the natural place to log app
/// launch/quit — the anchor points for reading an exported log.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        Log.ui.notice("applicationDidFinishLaunching: Recorgi \(version, privacy: .public), macOS \(osVersion, privacy: .public)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.ui.notice("applicationWillTerminate")
    }
}
