import SwiftUI
import RecorgiCore
import RecorgiCapture

public struct ContentView: View {
    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var settings: RecordingSettings
    @ObservedObject var engine: ScreenRecordingEngine

    @State private var isSettingsPresented = false

    public init(permissions: PermissionsManager, settings: RecordingSettings, engine: ScreenRecordingEngine) {
        self.permissions = permissions
        self.settings = settings
        self.engine = engine
    }

    public var body: some View {
        VStack(spacing: 20) {
            if permissions.microphoneStatus == .denied || permissions.screenRecordingStatus == .denied {
                PermissionsBanner(permissions: permissions)
            }

            RecordButton(engine: engine, settings: settings)

            HStack(spacing: 16) {
                SourceToggle(title: "Системный звук", systemImage: "speaker.wave.2.fill", isOn: $settings.isSystemAudioEnabled)
                SourceToggle(title: "Микрофон", systemImage: "mic.fill", isOn: $settings.isMicrophoneEnabled)
            }

            if let error = engine.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                isSettingsPresented = true
            } label: {
                Label("Настройки", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
        }
        .padding(28)
        .frame(width: 360)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(settings: settings)
        }
        .task {
            await permissions.requestAll()
        }
    }
}

private struct RecordButton: View {
    @ObservedObject var engine: ScreenRecordingEngine
    @ObservedObject var settings: RecordingSettings

    private var isRecording: Bool {
        if case .recording = engine.state { return true }
        return false
    }

    var body: some View {
        Button {
            Task {
                if isRecording {
                    await engine.stop()
                } else {
                    try? await engine.start(settings: settings)
                }
            }
        } label: {
            Circle()
                .fill(isRecording ? Color.red : Color.accentColor)
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: isRecording ? "stop.fill" : "record.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct SourceToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(.button)
    }
}
