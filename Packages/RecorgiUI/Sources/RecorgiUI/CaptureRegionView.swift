import SwiftUI
import AppKit
import RecorgiCore
import RecorgiCapture

struct CaptureRegionView: View {
    @ObservedObject var settings: RecordingSettings
    @State private var displays: [DisplayInfo] = []
    @State private var windows: [WindowInfo] = []
    @State private var loadError: String?
    @State private var isSelectingArea = false

    private let sourceProvider = CaptureSourceProvider()
    private let areaSelector = AreaSelector()
    private let areaHighlighter = AreaHighlighter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Область записи")
                    .font(.largeTitle.bold())

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Экран", systemImage: "display")
                            .font(.headline)

                        if displays.count > 1 {
                            // Multiple monitors: the distinction actually
                            // matters here — "Основной дисплей" follows
                            // whichever screen System Settings currently
                            // calls primary (can change), while picking a
                            // specific one locks to that physical display.
                            regionRow(
                                systemImage: "display",
                                title: "Основной дисплей",
                                subtitle: "Текущий главный экран — следует настройке системы",
                                isSelected: settings.captureRegion == .primaryDisplay
                            ) {
                                settings.captureRegion = .primaryDisplay
                            }

                            ForEach(displays) { display in
                                regionRow(
                                    systemImage: displayIcon(for: display),
                                    title: display.name,
                                    subtitle: "\(display.width)×\(display.height)",
                                    isSelected: settings.captureRegion == .display(display)
                                ) {
                                    settings.captureRegion = .display(display)
                                }
                            }
                        } else {
                            // Single monitor: "primary" and "this specific
                            // display" are the same thing, so show one row
                            // instead of two identical-looking options —
                            // using its real system name (e.g. "Built-in
                            // Display"), the same one System Settings shows.
                            regionRow(
                                systemImage: displays.first.map(displayIcon(for:)) ?? "display",
                                title: displays.first?.name ?? "Экран",
                                subtitle: displays.first.map { "\($0.width)×\($0.height)" },
                                isSelected: isSingleDisplaySelected
                            ) {
                                settings.captureRegion = .primaryDisplay
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Окно", systemImage: "macwindow")
                            .font(.headline)

                        if windows.isEmpty {
                            Text("Нет открытых окон")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(windows) { window in
                            regionRow(
                                icon: appIcon(for: window.processID),
                                title: window.title,
                                subtitle: window.appName,
                                isSelected: settings.captureRegion == .window(window)
                            ) {
                                settings.captureRegion = .window(window)
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Область", systemImage: "crop")
                            .font(.headline)

                        if case .area(let display, let rect) = settings.captureRegion {
                            areaPreview(display: display, rect: rect)
                            Text("\(Int(rect.width))×\(Int(rect.height)) на «\(display.name)»")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Выдели произвольный прямоугольник перетаскиванием, как в системном скриншоте (⌘⇧5)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button(isAreaSelected ? "Изменить область…" : "Выбрать область…") {
                            selectArea()
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .disabled(isSelectingArea || displays.isEmpty)
                    }
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

    /// Keeps the on-screen border in sync with the current selection — shown
    /// whenever an area is picked (and this page is open), hidden otherwise.
    private func syncHighlighter() {
        if case .area(let display, let rect) = settings.captureRegion {
            areaHighlighter.show(on: display.displayID, rect: rect)
        } else {
            areaHighlighter.hide()
        }
    }

    @ViewBuilder
    private func regionRow(icon: NSImage? = nil, systemImage: String? = nil, title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        // A ternary can't pick between GlassButtonStyle and
        // GlassProminentButtonStyle (different concrete types), so the
        // branch has to happen at the view level instead.
        if isSelected {
            regionButton(icon: icon, systemImage: systemImage, title: title, subtitle: subtitle, isSelected: true, action: action)
                .buttonStyle(.glassProminent)
        } else {
            regionButton(icon: icon, systemImage: systemImage, title: title, subtitle: subtitle, isSelected: false, action: action)
                .buttonStyle(.glass)
        }
    }

    private func regionButton(icon: NSImage?, systemImage: String?, title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .frame(width: 20, height: 20)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
        }
        .buttonBorderShape(.capsule)
    }

    private var isAreaSelected: Bool {
        if case .area = settings.captureRegion { return true }
        return false
    }

    /// A small to-scale map of the display with the selected rect
    /// highlighted, so it's obvious at a glance *where* the chosen area is —
    /// not just its width/height as numbers.
    private func areaPreview(display: DisplayInfo, rect: CGRect) -> some View {
        let aspect = display.height > 0 ? CGFloat(display.width) / CGFloat(display.height) : 16.0 / 10.0
        let previewWidth: CGFloat = 220
        let previewHeight = previewWidth / aspect

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

            Rectangle()
                .fill(Color.accentColor.opacity(0.35))
                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1.5))
                .frame(
                    width: previewWidth * (rect.width / CGFloat(display.width)),
                    height: previewHeight * (rect.height / CGFloat(display.height))
                )
                .offset(
                    x: previewWidth * (rect.minX / CGFloat(display.width)),
                    y: previewHeight * (rect.minY / CGFloat(display.height))
                )
        }
        .frame(width: previewWidth, height: previewHeight)
    }

    private func appIcon(for processID: Int32) -> NSImage? {
        NSRunningApplication(processIdentifier: processID)?.icon
    }

    /// Mirrors how System Settings distinguishes displays: a laptop glyph
    /// for the built-in panel, a plain monitor glyph for anything external.
    private func displayIcon(for display: DisplayInfo) -> String {
        display.name.localizedCaseInsensitiveContains("built-in") ? "laptopcomputer" : "display"
    }

    /// On a single-monitor setup, .primaryDisplay and .display(thatDisplay)
    /// are functionally identical — treat either as "selected" so the merged
    /// row still lights up correctly even if the region was picked before
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
