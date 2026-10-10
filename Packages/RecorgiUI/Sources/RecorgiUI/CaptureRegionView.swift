import SwiftUI
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
                                title: "Основной дисплей",
                                subtitle: "Текущий главный экран — следует настройке системы",
                                isSelected: settings.captureRegion == .primaryDisplay
                            ) {
                                settings.captureRegion = .primaryDisplay
                            }

                            ForEach(displays) { display in
                                regionRow(
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
                            // instead of two identical-looking options.
                            regionRow(
                                title: "Основной дисплей",
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
                            Text("Выбрано: \(Int(rect.width))×\(Int(rect.height)) на «\(display.name)»")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Выдели произвольный прямоугольник перетаскиванием, как в системном скриншоте (⌘⇧5)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button("Выбрать область…") {
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
    }

    @ViewBuilder
    private func regionRow(title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        // A ternary can't pick between GlassButtonStyle and
        // GlassProminentButtonStyle (different concrete types), so the
        // branch has to happen at the view level instead.
        if isSelected {
            regionButton(title: title, subtitle: subtitle, isSelected: true, action: action)
                .buttonStyle(.glassProminent)
        } else {
            regionButton(title: title, subtitle: subtitle, isSelected: false, action: action)
                .buttonStyle(.glass)
        }
    }

    private func regionButton(title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
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
