import SwiftUI
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

    private var startedAt: Date? {
        if case .recording(let date) = engine.state { return date }
        return nil
    }

    var body: some View {
        HStack(spacing: 20) {
            recordButton

            HStack(spacing: 14) {
                iconToggle(isOn: $settings.isSystemAudioEnabled, icon: "speaker.wave.2.fill", help: "Системный звук")
                iconToggle(isOn: $settings.isMicrophoneEnabled, icon: "mic.fill", help: "Микрофон")
            }

            Spacer()

            if isRecording {
                RecordingTimer(startedAt: startedAt)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(in: Capsule())
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
            Image(systemName: isRecording ? "stop.fill" : "record.circle")
                .font(.system(size: 18))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.glassProminent)
        .tint(isRecording ? .red : .accentColor)
    }

    private func iconToggle(isOn: Binding<Bool>, icon: String, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .help(help)
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
