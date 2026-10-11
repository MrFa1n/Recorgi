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
                .task {
                    if ProcessInfo.processInfo.environment["RECORGI_STRESS_TEST"] != nil {
                        await permissions.requestAll()
                        await StressTestRunner.run(engine: engine, settings: settings)
                    }
                }
        }
        .defaultSize(width: 940, height: 600)
    }
}
