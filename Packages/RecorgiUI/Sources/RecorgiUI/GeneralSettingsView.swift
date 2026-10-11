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
            .frame(maxWidth: .infinity, alignment: .leading)
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
