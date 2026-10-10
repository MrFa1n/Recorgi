import SwiftUI
import AppKit
import RecorgiCore
import RecorgiCapture

public struct SettingsView: View {
    @ObservedObject var settings: RecordingSettings
    @State private var microphones: [AudioInputDevice] = []
    @State private var outputDevices: [AudioOutputDevice] = []
    @State private var runningApps: [AudioApplication] = []
    @State private var appsLoadError: String?

    private let deviceProvider = AudioDeviceProvider()
    private let applicationProvider = RunningApplicationProvider()

    public init(settings: RecordingSettings) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section("Системный звук") {
                Toggle("Записывать системный звук", isOn: $settings.isSystemAudioEnabled)

                Picker("Источник", selection: $settings.systemAudioScope) {
                    Text("Весь системный звук").tag(SystemAudioScope.entireSystem)
                    if !runningApps.isEmpty {
                        Divider()
                        ForEach(runningApps) { app in
                            Text(app.name).tag(SystemAudioScope.application(app))
                        }
                    }
                }
                .disabled(!settings.isSystemAudioEnabled)

                if let appsLoadError {
                    Text(appsLoadError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Микрофон") {
                Toggle("Записывать микрофон", isOn: $settings.isMicrophoneEnabled)

                Picker("Устройство", selection: $settings.selectedMicrophoneID) {
                    Text("По умолчанию").tag(String?.none)
                    ForEach(microphones) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .disabled(!settings.isMicrophoneEnabled)

                Toggle("Слушать микрофон во время записи", isOn: $settings.isMonitoringEnabled)
                    .disabled(!settings.isMicrophoneEnabled)

                Picker("Куда выводить", selection: $settings.selectedMonitoringOutputID) {
                    Text("Системное устройство по умолчанию").tag(String?.none)
                    ForEach(outputDevices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .disabled(!settings.isMicrophoneEnabled || !settings.isMonitoringEnabled)
            }

            Section("Сохранение") {
                HStack {
                    Text(settings.saveDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Изменить…") {
                        chooseSaveDirectory()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 440, height: 420)
        .task {
            microphones = deviceProvider.availableMicrophones()
            outputDevices = deviceProvider.availableOutputDevices()
            do {
                runningApps = try await applicationProvider.availableApplications()
            } catch {
                appsLoadError = "Не удалось получить список приложений: \(error.localizedDescription)"
            }
        }
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
