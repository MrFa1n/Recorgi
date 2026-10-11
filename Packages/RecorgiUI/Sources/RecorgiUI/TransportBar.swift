import SwiftUI
import Combine
import RecorgiCore
import RecorgiCapture

/// Always-visible glass control pill, pinned to the bottom of the window
/// regardless of which sidebar page is open — same idea as Apple Music's
/// bottom playback bar.
struct TransportBar: View {
    @ObservedObject var engine: ScreenRecordingEngine
    @ObservedObject var settings: RecordingSettings

    private var isRecording: Bool {
        if case .recording = engine.state { return true }
        return false
    }

    private var isBusy: Bool {
        switch engine.state {
        case .starting, .stopping: return true
        case .idle, .recording: return false
        }
    }

    private var startedAt: Date? {
        if case .recording(let date) = engine.state { return date }
        return nil
    }

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                recordButton

                GlassToggleButton(systemImage: "speaker.wave.2.fill", isOn: $settings.isSystemAudioEnabled)
                    .help("Системный звук")

                GlassToggleButton(systemImage: "mic.fill", isOn: $settings.isMicrophoneEnabled)
                    .help("Микрофон")

                if isRecording {
                    RecordingTimer(startedAt: startedAt)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var recordButton: some View {
        Button {
            Task {
                if isRecording {
                    await engine.stop()
                } else {
                    try? await engine.start(settings: settings)
                }
            }
        } label: {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 40, height: 40)
            } else {
                Image(systemName: isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 18))
                    .frame(width: 40, height: 40)
            }
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .modifier(RecordButtonTint(isRecording: isRecording))
        .disabled(isBusy)
        .hoverCursor()
    }
}

/// Red while recording (always, regardless of theme), the user's chosen
/// accent color otherwise. Split out as its own modifier because a ternary
/// can't pick between two different `Color?` sources inline without an
/// `@Environment` read, which only a modifier/view can do.
private struct RecordButtonTint: ViewModifier {
    let isRecording: Bool
    @Environment(\.accentTint) private var accentTint

    func body(content: Content) -> some View {
        content.tint(isRecording ? .red : accentTint)
    }
}

private struct RecordingTimer: View {
    let startedAt: Date?
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(elapsed)
            .onReceive(timer) { now = $0 }
    }

    private var elapsed: String {
        guard let startedAt else { return "" }
        let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
