import AppKit

/// The only reason this exists: keeping Recorgi running (with its menu-bar
/// item still live) after the main window is closed, instead of the
/// default SwiftUI behavior of quitting once the last window goes away.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
