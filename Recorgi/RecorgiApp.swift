import SwiftUI
import RecorgiCore
import RecorgiCapture
import RecorgiUI

@main
struct RecorgiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var permissions = PermissionsManager()
    @StateObject private var settings = RecordingSettings()
    @StateObject private var engine = ScreenRecordingEngine()
    @StateObject private var hotkeys = GlobalHotkeyManager()
    @StateObject private var menuBar = MenuBarController()

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            ContentView(permissions: permissions, settings: settings, engine: engine)
                .frame(minWidth: 760, idealWidth: 940, minHeight: 480, idealHeight: 600)
                .background(WindowOpenerBridge(menuBar: menuBar))
                .task {
                    hotkeys.start(settings: settings, engine: engine)
                    menuBar.start(settings: settings, engine: engine)
                }
        }
        .defaultSize(width: 940, height: 600)
    }

    // OpenWindowAction has no parameterless callAsFunction overload on
    // this SDK — every one of them needs an explicit id (or a value), so
    // the WindowGroup needs one to reopen by.
    fileprivate static let mainWindowID = "main"
}

/// `@Environment(\.openWindow)` only resolves inside a SwiftUI view in the
/// window's own hierarchy — MenuBarController (plain AppKit/NSObject code)
/// has no way to read it directly, so this just captures the action once
/// and hands it over.
private struct WindowOpenerBridge: View {
    let menuBar: MenuBarController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear { menuBar.openWindowAction = { openWindow(id: RecorgiApp.mainWindowID) } }
    }
}
