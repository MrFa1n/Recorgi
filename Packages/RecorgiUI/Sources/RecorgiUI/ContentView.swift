import SwiftUI
import AppKit
import RecorgiCore
import RecorgiCapture

public struct ContentView: View {
    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var settings: RecordingSettings
    @ObservedObject var engine: ScreenRecordingEngine

    @State private var selection: SidebarSection? = .record
    @State private var showSplash = true

    public init(permissions: PermissionsManager, settings: RecordingSettings, engine: ScreenRecordingEngine) {
        self.permissions = permissions
        self.settings = settings
        self.engine = engine
    }

    public var body: some View {
        ZStack {
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
            // The sidebar-toggle button NavigationSplitView adds
            // automatically lives in the window's native toolbar, a layer
            // that sits above the SwiftUI content view entirely — no
            // z-index or overlay inside this view hierarchy can cover it,
            // which is why it kept showing up floating over the splash.
            // `.toolbar(removing: .sidebarToggle)` conditioned on
            // showSplash was tried first and didn't reliably react to the
            // state change; hiding the whole window toolbar outright does.
            .toolbar(showSplash ? .hidden : .visible, for: .windowToolbar)
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

            // On top of everything, briefly, every launch — a fixed
            // duration rather than tied to permissions.requestAll()
            // finishing: that call is near-instant anyway, and coupling
            // the brand moment's length to it would make the splash
            // flicker by inconsistently depending on system state instead
            // of playing out its own animation at a predictable pace.
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            scheduleSplashDismiss()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .record {
        case .record:
            RecordPageView(permissions: permissions, settings: settings, engine: engine, selection: $selection)
        case .recordings:
            RecordingsLibraryView(saveDirectory: settings.saveDirectory, settings: settings)
        case .captureRegion:
            CaptureRegionView(settings: settings)
        case .audioSources:
            AudioSourcesView(settings: settings)
        case .general:
            GeneralSettingsView(settings: settings, replaySplash: replaySplash)
        }
    }

    /// Lets General settings re-trigger the launch splash on demand,
    /// without quitting and reopening the app — mainly so its animation
    /// can be reviewed/tuned without a full relaunch each time, but a
    /// harmless, cheap thing to leave reachable afterwards too.
    private func replaySplash() {
        withAnimation(.easeIn(duration: 0.25)) {
            showSplash = true
        }
        scheduleSplashDismiss()
    }

    private func scheduleSplashDismiss() {
        Task {
            // Long enough for SplashView's own animation sequence (ears
            // perk + wiggle, blink, tongue flick) to fully play out and
            // settle for a beat before fading — see its own animate().
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeOut(duration: 0.4)) {
                showSplash = false
            }
        }
    }
}
