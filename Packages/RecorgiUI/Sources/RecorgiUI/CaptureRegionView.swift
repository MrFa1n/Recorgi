import SwiftUI
import AppKit
import RecorgiCore
import RecorgiCapture

private enum CaptureModeTab: Hashable {
    case screen, window, area

    var label: String {
        switch self {
        case .screen: return "Экран"
        case .window: return "Окно"
        case .area: return "Область"
        }
    }

    var systemImage: String {
        switch self {
        case .screen: return "display"
        case .window: return "macwindow"
        case .area: return "crop"
        }
    }
}

struct CaptureRegionView: View {
    @ObservedObject var settings: RecordingSettings
    @State private var mode: CaptureModeTab
    @State private var displays: [DisplayInfo] = []
    @State private var windows: [WindowInfo] = []
    @State private var loadError: String?
    @State private var isSelectingArea = false

    private let sourceProvider = CaptureSourceProvider()
    private let areaSelector = AreaSelector()
    // @State, not `let` — SwiftUI recreates this View struct on every
    // re-render, and a plain `let` would silently spawn a fresh
    // AreaHighlighter (with no handle to the window a previous instance
    // already showed) each time, orphaning the on-screen border so hide()
    // calls later stopped doing anything.
    @State private var areaHighlighter = AreaHighlighter()

    // .adaptive columns are supposed to be equal width on their own, but
    // the glass button styles apparently hug their content tightly enough
    // that even an explicit .frame(maxWidth: .infinity) on the Button
    // didn't make them fill the column — cards ended up visibly different
    // widths. Handing every card an *exact* .frame(width:) is a much
    // harder constraint than "up to infinity" and reliably wins — computed
    // once per body evaluation from a GeometryReader wrapping the whole
    // page (see body) and threaded down as a plain parameter, not measured
    // via a background GeometryReader + PreferenceKey: that measured the
    // very container the grid itself sizes, which is circular — the
    // measurement and the thing being measured kept chasing each other and
    // produced a visibly broken, oscillating layout.
    private let cardSpacing: CGFloat = 16
    private let minCardWidth: CGFloat = 200

    init(settings: RecordingSettings) {
        self._settings = ObservedObject(wrappedValue: settings)
        switch settings.captureRegion {
        case .primaryDisplay, .display:
            self._mode = State(initialValue: .screen)
        case .window:
            self._mode = State(initialValue: .window)
        case .area:
            self._mode = State(initialValue: .area)
        }
    }

    var body: some View {
        // Wraps the whole page: geo.size here comes from this page's own
        // allocated space in the window, which doesn't depend on anything
        // inside the ScrollView — unlike measuring a view that's itself
        // sized by the grid the measurement then feeds, this can't become
        // circular.
        GeometryReader { geo in
            let availableWidth = max(0, geo.size.width - 48) // the VStack's own 24pt padding, each side
            let columnCount = availableWidth > 0 ? max(1, Int((availableWidth + cardSpacing) / (minCardWidth + cardSpacing))) : 1
            let cardWidth: CGFloat = availableWidth > 0
                ? (availableWidth - CGFloat(columnCount - 1) * cardSpacing) / CGFloat(columnCount)
                : minCardWidth
            let gridColumns = Array(repeating: GridItem(.fixed(cardWidth), spacing: cardSpacing), count: columnCount)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Invisible but present in the hierarchy, so
                    // .keyboardShortcut claims Escape for the whole page
                    // regardless of what, if anything, currently has focus —
                    // the reliable way to handle a page-level shortcut in
                    // SwiftUI on macOS, rather than fighting over which view
                    // is first responder.
                    Button("", action: resetAreaSelection)
                        .keyboardShortcut(.escape, modifiers: [])
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)

                    Text("Область записи")
                        .font(.largeTitle.bold())

                    modePicker

                    switch mode {
                    case .screen: screenContent(gridColumns: gridColumns, cardWidth: cardWidth)
                    case .window: windowContent(gridColumns: gridColumns, cardWidth: cardWidth)
                    case .area: areaContent
                    }

                    if let loadError {
                        Text(loadError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            await loadSources()
        }
        .onAppear {
            // Only this page's own AreaHighlighter instance becomes
            // draggable — ScreenRecordingEngine owns a completely separate
            // one for the actual recording, which never calls this and
            // stays click-through.
            areaHighlighter.setInteractive(true)
            areaHighlighter.setAccentColor(themeNSColor)
            areaHighlighter.onRectChange = { newRect in
                if case .area(let display, _) = settings.captureRegion {
                    settings.captureRegion = .area(display, newRect)
                }
            }
            syncHighlighter()
        }
        .onChange(of: settings.captureRegion) {
            syncHighlighter()
        }
        .onChange(of: mode) {
            syncHighlighter()
        }
        .onChange(of: settings.accentColor) {
            areaHighlighter.setAccentColor(themeNSColor)
        }
        .onDisappear {
            areaHighlighter.hide()
        }
    }

    private var modePicker: some View {
        Picker("Режим", selection: $mode) {
            ForEach([CaptureModeTab.screen, .window, .area], id: \.self) { tab in
                Label(tab.label, systemImage: tab.systemImage).tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
    }

    // MARK: - Screen

    private func screenContent(gridColumns: [GridItem], cardWidth: CGFloat) -> some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: cardSpacing) {
            if displays.count > 1 {
                if let primary = displays.first {
                    sourceCard(
                        source: .display(primary.displayID),
                        title: "Основной дисплей",
                        subtitle: "Следует настройке системы",
                        isSelected: settings.captureRegion == .primaryDisplay,
                        cardWidth: cardWidth
                    ) {
                        settings.captureRegion = .primaryDisplay
                    }
                }

                ForEach(displays) { display in
                    sourceCard(
                        source: .display(display.displayID),
                        title: display.name,
                        subtitle: "\(display.width)×\(display.height)",
                        isSelected: settings.captureRegion == .display(display),
                        cardWidth: cardWidth
                    ) {
                        settings.captureRegion = .display(display)
                    }
                }
            } else if let only = displays.first {
                sourceCard(
                    source: .display(only.displayID),
                    title: only.name,
                    subtitle: "\(only.width)×\(only.height)",
                    isSelected: isSingleDisplaySelected,
                    cardWidth: cardWidth
                ) {
                    settings.captureRegion = .primaryDisplay
                }
            } else {
                Text("Нет доступных экранов")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Window

    private func windowContent(gridColumns: [GridItem], cardWidth: CGFloat) -> some View {
        Group {
            if windows.isEmpty {
                Text("Нет открытых окон")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: cardSpacing) {
                    ForEach(windows) { window in
                        sourceCard(
                            source: .window(window.windowID),
                            title: window.title,
                            subtitle: window.appName,
                            isSelected: settings.captureRegion == .window(window),
                            cardWidth: cardWidth
                        ) {
                            settings.captureRegion = .window(window)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Area

    private var areaContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if case .area(let display, let rect) = settings.captureRegion {
                areaPreview(display: display, rect: rect)
                Text("\(Int(rect.width))×\(Int(rect.height)) на «\(display.name)» · перетащи рамку на экране, чтобы подвинуть или изменить размер")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let primary = displays.first {
                areaPreview(display: primary, rect: nil)
                Text("Выдели произвольный прямоугольник перетаскиванием, как в системном скриншоте (⌘⇧5)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(isAreaSelected ? "Изменить область…" : "Выбрать область…") {
                selectArea()
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .disabled(isSelectingArea || displays.isEmpty)
            .hoverCursor()
        }
    }

    /// A real screenshot of the display, with the selected rect drawn as a
    /// highlighted crop box on top of it — so it's obvious at a glance
    /// *what* the chosen area actually contains, not just an abstract box
    /// with numbers.
    private func areaPreview(display: DisplayInfo, rect: CGRect?) -> some View {
        let aspect = display.height > 0 ? CGFloat(display.width) / CGFloat(display.height) : 16.0 / 10.0

        return ZStack(alignment: .topLeading) {
            SourceThumbnailView(source: .display(display.displayID), sizing: .aspectFit(aspect))

            if let rect, display.width > 0, display.height > 0 {
                GeometryReader { geo in
                    let scaleX = geo.size.width / CGFloat(display.width)
                    let scaleY = geo.size.height / CGFloat(display.height)
                    Rectangle()
                        .fill(themeColor.opacity(0.18))
                        .overlay(Rectangle().stroke(themeColor, lineWidth: 2))
                        .frame(width: rect.width * scaleX, height: rect.height * scaleY)
                        .offset(x: rect.minX * scaleX, y: rect.minY * scaleY)
                }
            }
        }
        .frame(maxWidth: 360)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Keeps the on-screen border in sync with the current selection — shown
    /// whenever an area is picked (and this page is open), hidden otherwise.
    /// Only shown while the Область tab is actually open — not whenever
    /// .area happens to be the saved selection. It used to track the saved
    /// selection alone, so switching to Экран/Окно while an area was picked
    /// left the border on screen behind the window; since this page's own
    /// live thumbnails capture the whole screen, the border ended up
    /// capturing *itself*, recursively, in every other tab's preview.
    private func syncHighlighter() {
        if mode == .area, case .area(let display, let rect) = settings.captureRegion {
            areaHighlighter.show(on: display.displayID, rect: rect)
        } else {
            areaHighlighter.hide()
        }
    }

    // MARK: - Source card

    // A ternary can't pick between GlassButtonStyle and
    // GlassProminentButtonStyle (different concrete types), so the branch
    // has to happen at the view level instead.
    @ViewBuilder
    private func sourceCard(source: SourceThumbnailView.Source, title: String, subtitle: String?, isSelected: Bool, cardWidth: CGFloat, action: @escaping () -> Void) -> some View {
        // An exact .frame(width:) on the Button, not .frame(maxWidth:
        // .infinity) — the glass button styles apparently hug their content
        // tightly enough that even an explicit maxWidth of infinity didn't
        // make them fill the grid column; an exact width is a much harder
        // constraint and reliably wins. cardWidth comes from the caller
        // (ultimately body's GeometryReader) so every card, in every row,
        // gets the identical value.
        if isSelected {
            sourceCardButton(source: source, title: title, subtitle: subtitle, isSelected: true, cardWidth: cardWidth, action: action)
                .buttonStyle(.glassProminent)
                .frame(width: cardWidth)
        } else {
            sourceCardButton(source: source, title: title, subtitle: subtitle, isSelected: false, cardWidth: cardWidth, action: action)
                .buttonStyle(.glass)
                .frame(width: cardWidth)
        }
    }

    // Thumbnail (130) + spacing (10) + text block (36) + vertical padding
    // (10 top + 10 bottom) — pinned explicitly on the outer VStack too, not
    // just its pieces, so the button's glass background can't end up a
    // different size per card for any reason this doesn't already account
    // for.
    private let sourceCardHeight: CGFloat = 196

    private func sourceCardButton(source: SourceThumbnailView.Source, title: String, subtitle: String?, isSelected: Bool, cardWidth: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    SourceThumbnailView(source: source)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, themeColor)
                            .font(.title3)
                            .padding(6)
                    }
                }

                // Fixed height for title+subtitle together (not just the
                // thumbnail) — two reserved lines regardless of whether
                // subtitle is actually present, so every card in the grid
                // is exactly the same height instead of each one hugging
                // its own content.
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(subtitle ?? " ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .opacity(subtitle == nil ? 0 : 1)
                }
                .padding(.horizontal, 2)
                .frame(height: 36, alignment: .top)
            }
            .padding(10)
            .frame(width: cardWidth, height: sourceCardHeight, alignment: .topLeading)
        }
        .buttonBorderShape(.roundedRectangle)
        .hoverCursor()
    }

    private var isAreaSelected: Bool {
        if case .area = settings.captureRegion { return true }
        return false
    }

    private var themeColor: Color {
        settings.accentColor?.color ?? Color.accentColor
    }

    private var themeNSColor: NSColor {
        settings.accentColor?.nsColor ?? .controlAccentColor
    }

    /// On a single-monitor setup, .primaryDisplay and .display(thatDisplay)
    /// are functionally identical — treat either as "selected" so the merged
    /// card still lights up correctly even if the region was picked before
    /// (e.g. a second monitor got unplugged since).
    private var isSingleDisplaySelected: Bool {
        if case .primaryDisplay = settings.captureRegion { return true }
        if case .display(let picked) = settings.captureRegion, picked == displays.first { return true }
        return false
    }

    private func loadSources() async {
        do {
            async let displaysTask = sourceProvider.availableDisplays()
            async let windowsTask = sourceProvider.availableWindows()
            displays = try await displaysTask
            windows = try await windowsTask
        } catch {
            loadError = "Не удалось получить список источников: \(error.localizedDescription)"
        }
    }

    private func selectArea() {
        // Keep this simple: area selection always targets the primary
        // display. Picking which display to draw the area on would need its
        // own UI step; most setups are single-monitor anyway.
        guard let primary = displays.first else { return }
        isSelectingArea = true
        Task {
            if let rect = await areaSelector.selectArea(on: primary.displayID) {
                settings.captureRegion = .area(primary, rect)
            }
            isSelectingArea = false
        }
    }

    /// Esc while an area is already picked: clear it and land back on a
    /// plain default — syncHighlighter() (driven by the resulting
    /// settings.captureRegion change) takes care of hiding the border.
    private func resetAreaSelection() {
        guard mode == .area, case .area = settings.captureRegion else { return }
        settings.captureRegion = .primaryDisplay
        NSApp.activate(ignoringOtherApps: true)
    }
}
