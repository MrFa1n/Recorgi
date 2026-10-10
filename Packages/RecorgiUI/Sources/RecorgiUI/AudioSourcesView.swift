import SwiftUI
import RecorgiCore
import RecorgiCapture

struct AudioSourcesView: View {
    @ObservedObject var settings: RecordingSettings
    @State private var microphones: [AudioInputDevice] = []
    @State private var outputDevices: [AudioOutputDevice] = []
    @State private var runningApps: [AudioApplication] = []
    @State private var appsLoadError: String?

    private let deviceProvider = AudioDeviceProvider()
    private let applicationProvider = RunningApplicationProvider()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Источники звука")
                    .font(.largeTitle.bold())

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Системный звук", systemImage: "speaker.wave.2.fill")
                            .font(.headline)

                        GlassToggleButton("Записывать системный звук", systemImage: "speaker.wave.2.fill", isOn: $settings.isSystemAudioEnabled)

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
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Микрофон", systemImage: "mic.fill")
                            .font(.headline)

                        GlassToggleButton("Записывать микрофон", systemImage: "mic.fill", isOn: $settings.isMicrophoneEnabled)

                        Picker("Устройство", selection: $settings.selectedMicrophoneID) {
                            Text("По умолчанию").tag(String?.none)
                            ForEach(microphones) { device in
                                Text(device.name).tag(Optional(device.id))
                            }
                        }
                        .disabled(!settings.isMicrophoneEnabled)

                        Divider()

                        GlassToggleButton("Слушать микрофон во время записи", systemImage: "headphones", isOn: $settings.isMonitoringEnabled)
                            .disabled(!settings.isMicrophoneEnabled)

                        Picker("Куда выводить", selection: $settings.selectedMonitoringOutputID) {
                            Text("Системное устройство по умолчанию").tag(String?.none)
                            ForEach(outputDevices) { device in
                                Text(device.name).tag(Optional(device.id))
                            }
                        }
                        .disabled(!settings.isMicrophoneEnabled || !settings.isMonitoringEnabled)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
}
