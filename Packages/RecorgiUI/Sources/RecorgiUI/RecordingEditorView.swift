import SwiftUI
import AVFoundation
import RecorgiCore
import RecorgiCapture

/// Minimal in-app video editor, opened from the Recordings library's play
/// button instead of handing the file off to an external player. Covers
/// trim (drag the two handles) and speed (0.5×–2×); "Сохранить как новый
/// файл" exports the result as a separate .mov next to the original —
/// the source recording is never modified in place.
struct RecordingEditorView: View {
    let recording: RecordingFile
    var onExported: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var duration: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var playhead: Double = 0
    @State private var isPlaying = false
    @State private var speed: Double = 1.0
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportError: String?
    @State private var timeObserverToken: Any?

    @State private var audioTrackLayout: AudioTrackLayout = .none
    @State private var isAudioSectionExpanded = false
    @State private var microphoneVolume = AudioTrackVolume()
    @State private var systemAudioVolume = AudioTrackVolume()
    @State private var combinedVolume = AudioTrackVolume()

    private enum AudioTrackLayout: Equatable {
        case none
        /// One track — mic and system audio already mixed together (older
        /// macOS), or only one of them was ever captured.
        case combined
        /// Two tracks — see VideoEditExporter.buildAudioMix's doc comment
        /// for how index 0/1 map to system audio/microphone.
        case separate
    }

    private let exporter = VideoEditExporter()
    private let speeds: [Double] = [0.5, 1.0, 1.5, 2.0]

    init(recording: RecordingFile, onExported: @escaping () -> Void) {
        self.recording = recording
        self.onExported = onExported
        _player = State(initialValue: AVPlayer(url: recording.url))
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(recording.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Готово") { dismiss() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .hoverCursor()
            }

            PlayerLayerView(player: player)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(minHeight: 320)

            transportRow

            // The audio section (two draggable-region timelines, when the
            // source has separate mic/system tracks) can easily grow taller
            // than this sheet's fixed frame — without a ScrollView that
            // content was simply unreachable below the window's bottom
            // edge, with no way to get to it. The export row stays outside,
            // always visible, since it's the primary action.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TrimScrubber(duration: duration, trimStart: $trimStart, trimEnd: $trimEnd, playhead: playhead, onSeek: seek)

                    if audioTrackLayout != .none {
                        audioSection
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Text("\(formatted(trimStart)) – \(formatted(trimEnd)) · длительность \(formatted(trimEnd - trimStart))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                exportButton
            }
        }
        .padding(24)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 540, idealHeight: 620)
        .task { await loadAsset() }
        .onDisappear { teardownPlayer() }
        .alert("Ошибка", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("ОК", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var transportRow: some View {
        HStack(spacing: 16) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .themedTint()
            .hoverCursor()

            Text(formatted(playhead))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                    .foregroundStyle(.secondary)

                // Picker's own label ("Скорость") is hidden: left to the
                // default, macOS lays it out *inside* the same row as the
                // segmented control, sharing its width — under any size
                // pressure (e.g. the sheet getting narrower) that text
                // column collapses and wraps one letter per line instead
                // of just truncating. The speedometer icon above already
                // says what this control does.
                Picker("Скорость", selection: $speed) {
                    ForEach(speeds, id: \.self) { value in
                        Text("\(formattedSpeed(value))×").tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .themedTint()
                .hoverCursor()
                .fixedSize()
                .onChange(of: speed) { _, newValue in
                    if isPlaying { player.rate = Float(newValue) }
                }
            }
        }
    }

    private var audioSection: some View {
        DisclosureGroup("Звук", isExpanded: $isAudioSectionExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                switch audioTrackLayout {
                case .separate:
                    VolumeRegionTimeline(duration: duration, trackLabel: "Системный звук", trackColor: .orange, baseGain: $systemAudioVolume.baseGain, regions: $systemAudioVolume.regions)
                    VolumeRegionTimeline(duration: duration, trackLabel: "Микрофон", trackColor: .blue, baseGain: $microphoneVolume.baseGain, regions: $microphoneVolume.regions)
                case .combined:
                    VolumeRegionTimeline(duration: duration, trackLabel: "Громкость записи", trackColor: .blue, baseGain: $combinedVolume.baseGain, regions: $combinedVolume.regions)
                case .none:
                    EmptyView()
                }
            }
            .padding(.top, 8)
        }
        .themedTint()
        .onChange(of: microphoneVolume) { _, _ in applyAudioMixToPlayer() }
        .onChange(of: systemAudioVolume) { _, _ in applyAudioMixToPlayer() }
        .onChange(of: combinedVolume) { _, _ in applyAudioMixToPlayer() }
    }

    private var exportButton: some View {
        Button {
            Task { await export() }
        } label: {
            if isExporting {
                HStack(spacing: 6) {
                    ProgressView(value: exportProgress)
                        .frame(width: 60)
                    Text("\(Int(exportProgress * 100))%")
                }
            } else {
                Label("Сохранить как новый файл", systemImage: "square.and.arrow.down")
            }
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .themedTint()
        .disabled(isExporting || duration <= 0)
        .hoverCursor()
    }

    private func loadAsset() async {
        let asset = player.currentItem?.asset ?? AVURLAsset(url: recording.url)
        guard let loadedDuration = try? await asset.load(.duration) else { return }
        duration = loadedDuration.seconds
        trimEnd = duration

        switch (try? await asset.loadTracks(withMediaType: .audio))?.count ?? 0 {
        case 0: audioTrackLayout = .none
        case 1: audioTrackLayout = .combined
        default: audioTrackLayout = .separate
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        // queue: .main guarantees this closure runs on the main thread, so
        // MainActor.assumeIsolated is safe here — the @Sendable closure type
        // AVPlayer requires doesn't by itself let the compiler see that.
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            MainActor.assumeIsolated {
                playhead = time.seconds
                if playhead >= trimEnd {
                    player.pause()
                    isPlaying = false
                    player.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600))
                    playhead = trimStart
                }
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if playhead < trimStart || playhead >= trimEnd {
                player.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600))
            }
            player.rate = Float(speed)
            isPlaying = true
        }
    }

    private func seek(to time: Double) {
        let clamped = min(max(time, 0), duration)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        playhead = clamped
    }

    private func teardownPlayer() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        player.pause()
    }

    /// Mirrors the chosen volume plan onto the live player so what's
    /// audible while editing matches what export() will actually bake in —
    /// same AVMutableAudioMix-building logic either way (see
    /// VideoEditExporter.buildAudioMix), just against the source asset's
    /// own tracks instead of a trimmed/sped-up composition's.
    private func applyAudioMixToPlayer() {
        guard let asset = player.currentItem?.asset else { return }
        Task {
            guard let tracks = try? await asset.loadTracks(withMediaType: .audio) else { return }
            player.currentItem?.audioMix = VideoEditExporter.buildAudioMix(
                tracks: tracks,
                microphoneVolume: microphoneVolume,
                systemAudioVolume: systemAudioVolume,
                combinedVolume: combinedVolume
            )
        }
    }

    private func export() async {
        isExporting = true
        exportProgress = 0
        let range = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: trimEnd, preferredTimescale: 600)
        )
        do {
            _ = try await exporter.export(
                sourceURL: recording.url,
                range: range,
                speed: speed,
                microphoneVolume: microphoneVolume,
                systemAudioVolume: systemAudioVolume,
                combinedVolume: combinedVolume
            ) { progress in
                exportProgress = progress
            }
            isExporting = false
            onExported()
            dismiss()
        } catch {
            isExporting = false
            exportError = error.localizedDescription
        }
    }

    private func formatted(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formattedSpeed(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}
