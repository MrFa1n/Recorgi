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
                .frame(minWidth: 760, idealWidth: 940, minHeight: 480, idealHeight: 600)
        }
        .defaultSize(width: 940, height: 600)
    }
}
