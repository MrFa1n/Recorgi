import SwiftUI
import AppKit
import RecorgiCore
import RecorgiCapture

public struct ContentView: View {
    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var settings: RecordingSettings
    @ObservedObject var engine: ScreenRecordingEngine

    @State private var isSettingsPresented = false
    @State private var microphones: [AudioInputDevice] = []

    private let deviceProvider = AudioDeviceProvider()

    public init(permissions: PermissionsManager, settings: RecordingSettings, engine: ScreenRecordingEngine) {
        self.permissions = permissions
        self.settings = settings
        self.engine = engine
    }

    public var body: some View {
        VStack(spacing: 20) {
            if permissions.microphoneStatus == .denied || permissions.screenRecordingStatus != .granted {
                PermissionsBanner(permissions: permissions)
            }

            RecordButton(engine: engine, settings: settings)

            HStack(spacing: 16) {
                SourceToggle(title: "Системный звук", systemImage: "speaker.wave.2.fill", isOn: $settings.isSystemAudioEnabled)

                HStack(spacing: 4) {
                    SourceToggle(title: "Микрофон", systemImage: "mic.fill", isOn: $settings.isMicrophoneEnabled)

                    Menu {
                        Button("По умолчанию") { settings.selectedMicrophoneID = nil }
                        if !microphones.isEmpty {
                            Divider()
                            ForEach(microphones) { device in
                                Button(device.name) { settings.selectedMicrophoneID = device.id }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(!settings.isMicrophoneEnabled)
                    .help(microphoneLabel)
                }
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
            microphones = deviceProvider.availableMicrophones()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Catches the common flow: banner → System Settings → grant →
            // switch back to Recorgi. Microphone updates immediately this
            // way; screen recording may still need a full quit-and-reopen,
            // which the banner explains.
            permissions.refresh()
        }
    }

    private var microphoneLabel: String {
        guard let id = settings.selectedMicrophoneID else { return "По умолчанию" }
        return microphones.first(where: { $0.id == id })?.name ?? "По умолчанию"
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
