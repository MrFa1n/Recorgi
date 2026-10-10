import SwiftUI
import AppKit
import RecorgiCore
import RecorgiCapture

public struct ContentView: View {
    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var settings: RecordingSettings
    @ObservedObject var engine: ScreenRecordingEngine

    @State private var selection: SidebarSection? = .record

    public init(permissions: PermissionsManager, settings: RecordingSettings, engine: ScreenRecordingEngine) {
        self.permissions = permissions
        self.settings = settings
        self.engine = engine
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            detail
                .safeAreaInset(edge: .bottom) {
                    TransportBar(engine: engine, settings: settings)
                }
        }
        .task {
            await permissions.requestAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Catches the common flow: banner → System Settings → grant →
            // switch back to Recorgi. Microphone updates immediately this
            // way; screen recording may still need a full quit-and-reopen,
            // which the banner explains.
            permissions.refresh()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .record {
        case .record:
            RecordPageView(permissions: permissions, settings: settings, engine: engine, selection: $selection)
        case .recordings:
            RecordingsLibraryView(saveDirectory: settings.saveDirectory)
        case .captureRegion:
            CaptureRegionView(settings: settings)
        case .audioSources:
            AudioSourcesView(settings: settings)
        case .general:
            GeneralSettingsView(settings: settings)
        }
    }
}
