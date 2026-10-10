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

    private let gridColumns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)]

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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Область записи")
                    .font(.largeTitle.bold())

                modePicker

                switch mode {
                case .screen: screenContent
                case .window: windowContent
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
        .task {
            await loadSources()
        }
        .onAppear {
            syncHighlighter()
        }
        .onChange(of: settings.captureRegion) {
            syncHighlighter()
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

    private var screenContent: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
            if displays.count > 1 {
                if let primary = displays.first {
                    sourceCard(
                        source: .display(primary.displayID),
                        title: "Основной дисплей",
                        subtitle: "Следует настройке системы",
                        isSelected: settings.captureRegion == .primaryDisplay
                    ) {
                        settings.captureRegion = .primaryDisplay
                    }
                }

                ForEach(displays) { display in
                    sourceCard(
                        source: .display(display.displayID),
                        title: display.name,
                        subtitle: "\(display.width)×\(display.height)",
                        isSelected: settings.captureRegion == .display(display)
                    ) {
                        settings.captureRegion = .display(display)
                    }
                }
            } else if let only = displays.first {
                sourceCard(
                    source: .display(only.displayID),
                    title: only.name,
                    subtitle: "\(only.width)×\(only.height)",
                    isSelected: isSingleDisplaySelected
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

    private var windowContent: some View {
        Group {
            if windows.isEmpty {
                Text("Нет открытых окон")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                    ForEach(windows) { window in
                        sourceCard(
                            source: .window(window.windowID),
                            title: window.title,
                            subtitle: window.appName,
                            isSelected: settings.captureRegion == .window(window)
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
                Text("\(Int(rect.width))×\(Int(rect.height)) на «\(display.name)»")
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
        }
    }

    /// A real screenshot of the display, with the selected rect drawn as a
    /// highlighted crop box on top of it — so it's obvious at a glance
    /// *what* the chosen area actually contains, not just an abstract box
    /// with numbers.
    private func areaPreview(display: DisplayInfo, rect: CGRect?) -> some View {
        let aspect = display.height > 0 ? CGFloat(display.width) / CGFloat(display.height) : 16.0 / 10.0

        return ZStack(alignment: .topLeading) {
            SourceThumbnailView(source: .display(display.displayID), aspectRatio: aspect)

            if let rect, display.width > 0, display.height > 0 {
                GeometryReader { geo in
                    let scaleX = geo.size.width / CGFloat(display.width)
                    let scaleY = geo.size.height / CGFloat(display.height)
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
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
    private func syncHighlighter() {
        if case .area(let display, let rect) = settings.captureRegion {
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
    private func sourceCard(source: SourceThumbnailView.Source, title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        if isSelected {
            sourceCardButton(source: source, title: title, subtitle: subtitle, isSelected: true, action: action)
                .buttonStyle(.glassProminent)
        } else {
            sourceCardButton(source: source, title: title, subtitle: subtitle, isSelected: false, action: action)
                .buttonStyle(.glass)
        }
    }

    private func sourceCardButton(source: SourceThumbnailView.Source, title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    SourceThumbnailView(source: source)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .font(.title3)
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonBorderShape(.roundedRectangle)
    }

    private var isAreaSelected: Bool {
        if case .area = settings.captureRegion { return true }
        return false
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
}
