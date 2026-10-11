import SwiftUI
import AppKit
import RecorgiCore

struct GeneralSettingsView: View {
    @ObservedObject var settings: RecordingSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Основные")
                    .font(.largeTitle.bold())

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Папка для записей", systemImage: "folder.fill")
                            .font(.headline)

                        HStack {
                            Text(settings.saveDirectory.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Изменить…") {
                                chooseSaveDirectory()
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .hoverCursor()
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Формат записи", systemImage: "film.fill")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Кодек")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Picker("Кодек", selection: $settings.videoCodec) {
                                ForEach(VideoCodec.allCases, id: \.self) { codec in
                                    Text(codec.label).tag(codec)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .tint(themeColor)
                            Text(settings.videoCodec.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Контейнер")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Picker("Контейнер", selection: $settings.videoContainer) {
                                ForEach(VideoContainer.allCases, id: \.self) { container in
                                    Text(container.label).tag(container)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .tint(themeColor)
                        }

                        // Neither recording path exposes an actual bitrate
                        // control — this adjusts resolution/frame rate
                        // instead, the one thing we do fully control
                        // ourselves on both paths. See RecordingQuality's
                        // own doc comment.
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Степень сжатия")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Picker("Степень сжатия", selection: $settings.recordingQuality) {
                                ForEach(RecordingQuality.allCases, id: \.self) { quality in
                                    Text(quality.label).tag(quality)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .tint(themeColor)
                            Text(settings.recordingQuality.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Горячие клавиши", systemImage: "keyboard.fill")
                            .font(.headline)

                        Text("Работают всегда, даже когда Recorgi не в фокусе. Нужен хотя бы один модификатор (⌘⌥⌃⇧)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 12) {
                            hotkeyRow(title: "Старт/стоп записи", binding: $settings.startStopHotkey)
                            hotkeyRow(title: "Микрофон", binding: $settings.toggleMicrophoneHotkey)
                            hotkeyRow(title: "Системный звук", binding: $settings.toggleSystemAudioHotkey)
                        }

                        if hasDuplicateHotkeys {
                            Label("Две из этих комбинаций совпадают — сработает только одна", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Button("Сбросить по умолчанию") {
                            settings.resetHotkeysToDefaults()
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .hoverCursor()
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Тема", systemImage: "circle.lefthalf.filled")
                            .font(.headline)

                        Picker("Тема", selection: $settings.appearanceMode) {
                            Label("Системная", systemImage: "circle.lefthalf.filled")
                                .tag(AppearanceMode?.none)
                            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                Label(mode.label, systemImage: mode.systemImage)
                                    .tag(AppearanceMode?.some(mode))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .tint(themeColor)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Цвет акцента", systemImage: "paintpalette.fill")
                            .font(.headline)

                        Text("Применяется к акцентным элементам — кнопке записи, рамке области захвата и т.п.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 14) {
                            systemSwatch
                            ForEach(AccentColorPreset.allCases, id: \.self) { preset in
                                presetSwatch(preset)
                            }
                        }

                        Divider()

                        // Label intentionally left visible (no
                        // .labelsHidden()): hidden, this native control is
                        // just a bare color swatch with no text or icon —
                        // indistinguishable from a random button. The label
                        // plus the standard system swatch is what makes it
                        // read as "tap to pick a custom color", the same as
                        // every other native color picker in macOS.
                        ColorPicker("Свой цвет", selection: customColorBinding, supportsOpacity: false)
                    }
                }
            }
            .padding(24)
            // maxHeight too, not just maxWidth — ScrollView centers
            // content vertically by default on macOS when it's shorter
            // than the viewport, which on this page (short enough to not
            // always need scrolling) let a card drift down far enough to
            // sit under the floating TransportBar, stealing its clicks.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Follows System Settings > Appearance — the original, still-default
    /// behavior. The rainbow fill mirrors how System Settings marks its own
    /// "Multicolor" option, repurposed here to mean "dynamic/system" rather
    /// than literally multicolored UI.
    private var systemSwatch: some View {
        Button {
            settings.accentColor = nil
        } label: {
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [.blue, .purple, .pink, .red, .orange, .yellow, .green, .blue], center: .center))
                if settings.accentColor == nil {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: 2)
                        .padding(-3)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .hoverCursor()
        .help("Следовать системному акцентному цвету")
    }

    private func presetSwatch(_ preset: AccentColorPreset) -> some View {
        let isSelected = settings.accentColor == preset.choice
        return Button {
            settings.accentColor = preset.choice
        } label: {
            ZStack {
                Circle().fill(preset.choice.color)
                if isSelected {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: 2)
                        .padding(-3)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .hoverCursor()
        .help(preset.label)
    }

    private func hotkeyRow(title: String, binding: Binding<HotkeyBinding?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            HotkeyRecorderField(binding: binding)
        }
    }

    private var hasDuplicateHotkeys: Bool {
        let bindings = [settings.startStopHotkey, settings.toggleMicrophoneHotkey, settings.toggleSystemAudioHotkey]
            .compactMap { $0 }
        return Set(bindings.map { "\($0.keyCode)-\($0.modifiers.rawValue)" }).count != bindings.count
    }

    private var themeColor: Color {
        settings.accentColor?.color ?? Color.accentColor
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { settings.accentColor?.color ?? Color.accentColor },
            set: { settings.accentColor = AccentColorChoice(color: $0) }
        )
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url
        }
    }
}
