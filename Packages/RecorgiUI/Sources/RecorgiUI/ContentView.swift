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
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            // .overlay, not .safeAreaInset: safeAreaInset reserves a
            // hit-testable strip across the *entire width* of the detail
            // pane for its content, not just wherever that content
            // actually draws something — once a page scrolled far enough
            // that other content lined up with that strip, clicks there
            // died even nowhere near the visibly-drawn buttons. .overlay
            // sizes and hit-tests to its content's own natural size
            // (bottom-center here), nothing wider.
            detail
                .overlay(alignment: .bottom) {
                    TransportBar(engine: engine, settings: settings)
                }
        }
        .background(WindowTitleHider().frame(width: 0, height: 0))
        // The "Recorgi" text at the top wasn't the window's own title bar
        // text at all — NavigationSplitView adds a separate SwiftUI-drawn
        // toolbar item for the title (ToolbarDefaultItemKind.title), which
        // NSWindow.titleVisibility above has no effect on. Removing that
        // toolbar item outright, rather than emptying its text, is also
        // what lets everything below shift up into the freed space instead
        // of leaving a blank gap where it used to sit.
        .toolbar(removing: .title)
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
