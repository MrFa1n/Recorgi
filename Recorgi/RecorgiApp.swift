import SwiftUI
import RecorgiCore
import RecorgiCapture
import RecorgiUI

@main
struct RecorgiApp: App {
    @StateObject private var permissions = PermissionsManager()
    @StateObject private var settings = RecordingSettings()
    @StateObject private var engine = ScreenRecordingEngine()

    var body: some Scene {
        WindowGroup {
            ContentView(permissions: permissions, settings: settings, engine: engine)
        }
        .windowResizability(.contentSize)
    }
}
