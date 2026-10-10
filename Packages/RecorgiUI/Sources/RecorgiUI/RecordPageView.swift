import SwiftUI
import RecorgiCore
import RecorgiCapture

struct RecordPageView: View {
    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var settings: RecordingSettings
    @ObservedObject var engine: ScreenRecordingEngine

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

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Экран", systemImage: "rectangle.on.rectangle")
                            .font(.headline)
                        Text(captureRegionSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Настрой на вкладке «Область записи»")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    sourceCard(
                        title: "Системный звук",
                        systemImage: "speaker.wave.2.fill",
                        isOn: $settings.isSystemAudioEnabled,
                        summary: systemAudioSummary
                    )
                    sourceCard(
                        title: "Микрофон",
                        systemImage: "mic.fill",
                        isOn: $settings.isMicrophoneEnabled,
                        summary: settings.isMicrophoneEnabled ? "Включён" : "Выключен"
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

    private func sourceCard(title: String, systemImage: String, isOn: Binding<Bool>, summary: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                GlassToggleButton("Записывать", systemImage: systemImage, isOn: isOn)
                Text("Настрой источник на вкладке «Источники звука»")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
}
