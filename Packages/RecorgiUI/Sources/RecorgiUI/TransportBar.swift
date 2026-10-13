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

    private var isPaused: Bool {
        if case .paused = engine.state { return true }
        return false
    }

    /// Whether the record/stop button should show "stop" and a pause
    /// button should be available at all — recording and paused are both
    /// "a recording session is in progress" as far as that's concerned.
    private var isRecordingOrPaused: Bool {
        isRecording || isPaused
    }

    private var isBusy: Bool {
        switch engine.state {
        case .starting, .stopping, .pausing, .resuming: return true
        case .idle, .recording, .paused: return false
        }
    }

    private var startedAt: Date? {
        if case .recording(let date) = engine.state { return date }
        return nil
    }

    /// Frozen elapsed time to show while paused — `pausedAt - startedAt`,
    /// not re-derived from `now` like the running timer, since it
    /// shouldn't keep advancing.
    private var pausedElapsed: TimeInterval? {
        if case .paused(let startedAt, let pausedAt) = engine.state {
            return pausedAt.timeIntervalSince(startedAt)
        }
        return nil
    }

    var body: some View {
        // Plain HStack, not GlassEffectContainer: the container shares one
        // backing plate across its children for the Liquid Glass merge
        // effect, and that plate spans the *gaps* between the circle and
        // the two pills too, not just the buttons — eating clicks meant
        // for whatever page content sits underneath (this bar floats over
        // every page via .safeAreaInset). Tried gating that with
        // .allowsHitTesting(false) on the container and (true) back on
        // each button, but an ancestor's allowsHitTesting(false) actually
        // wins over a descendant's (true) — SwiftUI applies the
        // *outermost* value, not the innermost — so that disabled the
        // buttons too. A plain HStack never had a shared backing plate to
        // begin with, so there's nothing to gate: each button is hit-
        // testable exactly where it's drawn, nowhere else. The 3 buttons
        // never move relative to each other, so the morph/merge visual
        // GlassEffectContainer exists for wasn't doing anything here
        // anyway.
        HStack(spacing: 16) {
            recordButton

            if isRecordingOrPaused {
                pauseResumeButton
            }

            GlassToggleButton(systemImage: "speaker.wave.2.fill", isOn: $settings.isSystemAudioEnabled)
                .help("Системный звук")

            GlassToggleButton(systemImage: "mic.fill", isOn: $settings.isMicrophoneEnabled)
                .help("Микрофон")

            if isRecording {
                RecordingTimer(startedAt: startedAt)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            } else if let pausedElapsed {
                Text(Self.formatted(pausedElapsed))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var recordButton: some View {
        Button {
            Task {
                if isRecordingOrPaused {
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
                Image(systemName: isRecordingOrPaused ? "stop.fill" : "record.circle")
                    .font(.system(size: 18))
                    .frame(width: 40, height: 40)
            }
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .modifier(RecordButtonTint(isRecording: isRecording, isPaused: isPaused))
        .disabled(isBusy)
        .hoverCursor()
    }

    private var pauseResumeButton: some View {
        Button {
            Task {
                if isPaused {
                    await engine.resume()
                } else {
                    await engine.pause()
                }
            }
        } label: {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 14))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(isBusy)
        .hoverCursor()
        .help(isPaused ? "Продолжить запись" : "Приостановить запись")
    }

    private static func formatted(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// Red while actually recording, orange while paused (both regardless of
/// theme, same reasoning as before — a status that shouldn't blend in with
/// the user's chosen accent color), the user's chosen accent color
/// otherwise. Split out as its own modifier because a ternary can't pick
/// between different `Color?` sources inline without an `@Environment`
/// read, which only a modifier/view can do.
private struct RecordButtonTint: ViewModifier {
    let isRecording: Bool
    let isPaused: Bool
    @Environment(\.accentTint) private var accentTint

    func body(content: Content) -> some View {
        let tint: Color? = isRecording ? .red : (isPaused ? .orange : accentTint)
        content.tint(tint)
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
