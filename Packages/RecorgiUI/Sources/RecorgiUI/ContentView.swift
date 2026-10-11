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
        // Deliberately NOT a blanket .tint() here — Liquid Glass's plain
        // .glass button style turns out to pick up ambient .tint() too, not
        // just .glassProminent, so a global override recolored buttons that
        // were never blue (e.g. the "Изменить…" folder picker). Instead this
        // just carries the choice down via a separate environment key; each
        // already-blue control opts in explicitly with .themedTint(). See
        // AccentTint.swift.
        .environment(\.accentTint, settings.accentColor?.color)
        // nil means "follow the system" (same as never setting this
        // modifier at all) — a non-nil value forces the whole window
        // (including native AppKit chrome like the title bar) to that
        // appearance regardless of System Settings.
        .preferredColorScheme(settings.appearanceMode.map { $0 == .light ? .light : .dark })
        // nil means GlassCard keeps following the real, live system Reduce
        // Transparency setting — a non-nil choice overrides it for this
        // app. See TransparencyOverride.swift for why this needs its own
        // environment key instead of overriding SwiftUI's own
        // accessibilityReduceTransparency (it's get-only here).
        .environment(\.transparencyOverride, settings.transparencyMode)
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
