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
    // Mute reuses the same real CoreAudio hardware lever as the volume
    // slider (there's no separate "recording-only" mute for a live
    // hardware setting) — remembers the pre-mute percentage so unmuting
    // restores it exactly, rather than snapping to 100%.
    @State private var isMicrophoneMuted = false
    @State private var microphoneVolumeBeforeMute: Double = 100
    @State private var isPreviewingMicrophone = false
    // @State, not `let` — AVAudioEngine instance needs to survive this
    // View struct being recreated on every re-render, same reasoning as
    // CaptureRegionView's AreaHighlighter.
    @State private var livePreviewEngine = MicrophoneLivePreviewEngine()
    @State private var previewError: String?

    private let deviceProvider = AudioDeviceProvider()
    private let applicationProvider = RunningApplicationProvider()

    private var themeColor: Color {
        settings.accentColor?.color ?? Color.accentColor
    }

    /// Live system-audio volume/mute only means anything when scoped to
    /// one specific app — see RecordingSettings.systemAudioVolume's own
    /// doc comment for why "entire system" can't offer it.
    private var isSystemAudioAppScoped: Bool {
        if case .application = settings.systemAudioScope { true } else { false }
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

                        Divider()

                        if isSystemAudioAppScoped {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Громкость")
                                    Spacer()
                                    Text("\(Int((settings.systemAudioVolume * 100).rounded()))%")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                    Button {
                                        settings.isSystemAudioMuted.toggle()
                                    } label: {
                                        Image(systemName: settings.isSystemAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    }
                                    .buttonStyle(.borderless)
                                    .help(settings.isSystemAudioMuted ? "Включить звук" : "Приглушить")
                                    .hoverCursor()
                                    Button {
                                        settings.systemAudioVolume = 1.0
                                    } label: {
                                        Image(systemName: "arrow.counterclockwise")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Сбросить до 100%")
                                    .disabled(settings.systemAudioVolume == 1.0)
                                    .hoverCursor()
                                }
                                Slider(value: $settings.systemAudioVolume, in: 0...1, step: 0.01)
                                    .labelsHidden()
                                    .tint(themeColor)
                                    .disabled(settings.isSystemAudioMuted)
                                Text("Применяется сразу — можно крутить и до, и во время записи этого приложения")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .disabled(!settings.isSystemAudioEnabled)
                        } else {
                            Text("Живая громкость доступна только при записи звука одного приложения, а не всей системы")
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
                                    toggleMicrophoneMute()
                                } label: {
                                    Image(systemName: isMicrophoneMuted ? "mic.slash.fill" : "mic.fill")
                                }
                                .buttonStyle(.borderless)
                                .help(isMicrophoneMuted ? "Включить микрофон" : "Приглушить")
                                .hoverCursor()
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
                                .disabled(isMicrophoneMuted)
                                .onChange(of: microphoneVolumePercent) { _, newValue in
                                    applyMicrophoneVolume(percent: newValue)
                                }
                            Text("Меняет громкость входа самого микрофона в системе — действует сразу, независимо от того, идёт запись или нет")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .disabled(!settings.isMicrophoneEnabled)

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Шумоподавление микрофона")
                            Picker("Шумоподавление микрофона", selection: $settings.microphoneNoiseSuppression) {
                                ForEach(NoiseSuppressionLevel.allCases) { level in
                                    Text(level.displayName).tag(level)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .tint(themeColor)
                            .hoverCursor()
                            .onChange(of: settings.microphoneNoiseSuppression) { _, newLevel in
                                livePreviewEngine.setLevel(newLevel)
                            }

                            GlassToggleButton(
                                isPreviewingMicrophone ? "Остановить прослушивание" : "Прослушать микрофон",
                                systemImage: "waveform",
                                isOn: $isPreviewingMicrophone
                            )
                            .onChange(of: isPreviewingMicrophone) { _, isOn in
                                if isOn {
                                    let started = livePreviewEngine.start(
                                        microphoneDeviceUID: settings.selectedMicrophoneID,
                                        outputDeviceUID: settings.selectedMonitoringOutputID,
                                        level: settings.microphoneNoiseSuppression
                                    )
                                    if !started {
                                        previewError = livePreviewEngine.lastError ?? "Не удалось запустить прослушивание."
                                        isPreviewingMicrophone = false
                                    }
                                } else {
                                    livePreviewEngine.stop()
                                }
                            }

                            Text("Чтобы услышать микрофон с выбранным уровнем шумоподавления — работает до записи и во время неё, пока эта страница открыта. Сам уровень применяется к сохранённому файлу позже, в редакторе записи.")
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
        .onChange(of: settings.isMicrophoneEnabled) { _, isEnabled in
            if !isEnabled {
                isPreviewingMicrophone = false
                livePreviewEngine.stop()
            }
        }
        // Leaving this page while previewing would otherwise leave the
        // engine (and its hold on the microphone) running silently in the
        // background with no visible toggle left to turn it back off.
        .onDisappear {
            if isPreviewingMicrophone {
                isPreviewingMicrophone = false
                livePreviewEngine.stop()
            }
        }
        .alert("Ошибка", isPresented: Binding(
            get: { previewError != nil },
            set: { if !$0 { previewError = nil } }
        )) {
            Button("ОК", role: .cancel) { previewError = nil }
        } message: {
            Text(previewError ?? "")
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
        // Switching devices while muted shouldn't un-mute the new device —
        // carry the mute over by forcing it to 0 too.
        if isMicrophoneMuted {
            MicrophoneVolumeController.setVolume(0, deviceUID: settings.selectedMicrophoneID)
        }
    }

    private func applyMicrophoneVolume(percent: Double) {
        let scalar = percent / 100
        settings.microphoneVolume = scalar
        MicrophoneVolumeController.setVolume(Float(scalar), deviceUID: settings.selectedMicrophoneID)
    }

    /// Mute goes straight to the CoreAudio device, bypassing
    /// applyMicrophoneVolume on purpose — muting shouldn't overwrite the
    /// persisted volume choice with 0, it should just silence the hardware
    /// until unmuted, then restore exactly what was there before.
    private func toggleMicrophoneMute() {
        if isMicrophoneMuted {
            isMicrophoneMuted = false
            MicrophoneVolumeController.setVolume(Float(microphoneVolumeBeforeMute / 100), deviceUID: settings.selectedMicrophoneID)
        } else {
            microphoneVolumeBeforeMute = microphoneVolumePercent
            isMicrophoneMuted = true
            MicrophoneVolumeController.setVolume(0, deviceUID: settings.selectedMicrophoneID)
        }
    }
}
