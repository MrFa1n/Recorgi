import SwiftUI
import RecorgiCore
import RecorgiCapture

struct RecordPageView: View {
    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var settings: RecordingSettings
    @ObservedObject var engine: ScreenRecordingEngine
    @Binding var selection: SidebarSection?

    private var isRecording: Bool {
        if case .recording = engine.state { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if permissions.microphoneStatus == .denied || permissions.screenRecordingStatus != .granted {
                    PermissionsBanner(permissions: permissions)
                }

                if let error = engine.lastError {
                    GlassCard {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                sourceCard(
                    title: "Экран",
                    systemImage: "rectangle.on.rectangle",
                    summary: captureRegionSummary,
                    destination: .captureRegion
                )

                HStack(alignment: .top, spacing: 16) {
                    sourceCard(
                        title: "Системный звук",
                        systemImage: "speaker.wave.2.fill",
                        summary: systemAudioSummary,
                        destination: .audioSources,
                        isOn: $settings.isSystemAudioEnabled
                    )
                    sourceCard(
                        title: "Микрофон",
                        systemImage: "mic.fill",
                        summary: microphoneSummary,
                        destination: .audioSources,
                        isOn: $settings.isMicrophoneEnabled
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recorgi")
                .font(.largeTitle.bold())
            Text(isRecording ? "Идёт запись…" : "Готово к записи")
                .font(.title3)
                .foregroundStyle(isRecording ? .red : .secondary)
        }
    }

    /// A source card with an optional on/off toggle (audio sources) or none
    /// (screen — that's a pick, not a switch). Either way it always ends in
    /// an "Изменить" link that jumps straight to the page where it's
    /// actually configured, instead of just naming that page.
    private func sourceCard(
        title: String,
        systemImage: String,
        summary: String,
        destination: SidebarSection,
        isOn: Binding<Bool>? = nil
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                    Spacer()
                    if let isOn {
                        GlassToggleButton(systemImage: isOn.wrappedValue ? "checkmark" : "xmark", isOn: isOn)
                            .help(isOn.wrappedValue ? "Выключить запись" : "Включить запись")
                    }
                }

                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    selection = destination
                } label: {
                    HStack(spacing: 2) {
                        Text("Изменить")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .tint(settings.accentColor?.color)
                .foregroundStyle(.tint)
                .hoverCursor()
            }
        }
    }

    private var captureRegionSummary: String {
        switch settings.captureRegion {
        case .primaryDisplay: return "Основной дисплей"
        case .display(let d): return d.name
        case .window(let w): return "Окно: \(w.title.isEmpty ? w.appName : w.title)"
        case .area(let d, let rect): return "Область \(Int(rect.width))×\(Int(rect.height)) на «\(d.name)»"
        }
    }

    private var systemAudioSummary: String {
        guard settings.isSystemAudioEnabled else { return "Выключено" }
        switch settings.systemAudioScope {
        case .entireSystem: return "Весь системный звук"
        case .application(let app): return app.name
        }
    }

    private var microphoneSummary: String {
        settings.isMicrophoneEnabled ? "Включён" : "Выключен"
    }
}
