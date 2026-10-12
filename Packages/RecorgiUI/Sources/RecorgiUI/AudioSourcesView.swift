import SwiftUI
import RecorgiCore
import RecorgiCapture

struct AudioSourcesView: View {
    @ObservedObject var settings: RecordingSettings
    @State private var microphones: [AudioInputDevice] = []
    @State private var outputDevices: [AudioOutputDevice] = []
    @State private var runningApps: [AudioApplication] = []
    @State private var appsLoadError: String?
    // 0...100 — mirrors CoreAudio's own 0...1 scalar as a percentage, which
    // reads more naturally on a slider than a fraction. Kept as a separate
    // @State rather than binding the Slider straight to
    // settings.microphoneVolume: that property is nil until the user
    // actually touches this control (see its own doc comment), but the
    // Slider itself always needs a concrete number to show — this starts
    // out mirroring the device's real current hardware volume instead.
    @State private var microphoneVolumePercent: Double = 100

    private let deviceProvider = AudioDeviceProvider()
    private let applicationProvider = RunningApplicationProvider()

    private var themeColor: Color {
        settings.accentColor?.color ?? Color.accentColor
    }

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

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Громкость микрофона")
                                Spacer()
                                Text("\(Int(microphoneVolumePercent.rounded()))%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Button {
                                    microphoneVolumePercent = 100
                                    applyMicrophoneVolume(percent: 100)
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                .buttonStyle(.borderless)
                                .help("Сбросить до 100%")
                                .disabled(microphoneVolumePercent == 100)
                                .hoverCursor()
                            }
                            Slider(value: $microphoneVolumePercent, in: 0...100, step: 1)
                                .labelsHidden()
                                .tint(themeColor)
                                .onChange(of: microphoneVolumePercent) { _, newValue in
                                    applyMicrophoneVolume(percent: newValue)
                                }
                            Text("Меняет громкость входа самого микрофона в системе — действует сразу, независимо от того, идёт запись или нет")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
            // Extra bottom clearance for the floating TransportBar — see
            // GeneralSettingsView's own comment on this same line.
            .padding(.bottom, 76)
            // maxHeight too — see GeneralSettingsView's own comment on
            // this same line: ScrollView centers short content vertically
            // by default on macOS, which could let a card drift down
            // under the floating TransportBar.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            microphones = deviceProvider.availableMicrophones()
            outputDevices = deviceProvider.availableOutputDevices()
            syncMicrophoneVolumeDisplay()
            do {
                runningApps = try await applicationProvider.availableApplications()
            } catch {
                appsLoadError = "Не удалось получить список приложений: \(error.localizedDescription)"
            }
        }
        .onChange(of: settings.selectedMicrophoneID) {
            syncMicrophoneVolumeDisplay()
        }
    }

    /// Shows the newly-selected microphone's own real current volume if the
    /// user has never touched this slider, or re-applies their chosen
    /// percentage onto it otherwise — called on first appearance and every
    /// time the selected device changes.
    private func syncMicrophoneVolumeDisplay() {
        if let saved = settings.microphoneVolume {
            microphoneVolumePercent = (saved * 100).rounded()
            MicrophoneVolumeController.setVolume(Float(saved), deviceUID: settings.selectedMicrophoneID)
        } else if let current = MicrophoneVolumeController.currentVolume(deviceUID: settings.selectedMicrophoneID) {
            microphoneVolumePercent = (Double(current) * 100).rounded()
        } else {
            microphoneVolumePercent = 100
        }
    }

    private func applyMicrophoneVolume(percent: Double) {
        let scalar = percent / 100
        settings.microphoneVolume = scalar
        MicrophoneVolumeController.setVolume(Float(scalar), deviceUID: settings.selectedMicrophoneID)
    }
}
