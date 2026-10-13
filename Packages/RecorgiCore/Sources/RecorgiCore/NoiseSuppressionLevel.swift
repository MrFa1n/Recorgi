/// How aggressively the microphone's background noise gets gated down —
/// chosen in Audio Sources settings (and live-previewable there, see
/// MicrophoneLivePreviewEngine in RecorgiCapture) and applied for real in
/// the recording editor/export (see MicrophoneNoiseSuppressor, also
/// RecorgiCapture). Lives here, not in RecorgiCapture, purely because it's
/// a plain choice enum with no AVFoundation/AudioToolbox import of its
/// own — same reasoning as RecordingQuality, CaptureRegion, etc.
public enum NoiseSuppressionLevel: String, CaseIterable, Identifiable, Hashable, Sendable {
    case off, light, medium, strong

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Выключено"
        case .light: return "Слабое"
        case .medium: return "Среднее"
        case .strong: return "Сильное"
        }
    }

    /// Below this level (dBFS, measured by a short attack/release envelope
    /// follower, not raw sample amplitude), the signal is treated as
    /// background noise and attenuated. Public so RecorgiCapture's
    /// NoiseGateContext can read it — see RecordingQuality's maxDimension/
    /// frameRate for the same "tuning constant lives on the choice enum"
    /// precedent.
    public var thresholdDB: Float {
        switch self {
        case .off: return 0
        case .light: return -50
        case .medium: return -42
        case .strong: return -34
        }
    }

    /// How far a fully-gated moment gets attenuated, in dB.
    public var maxReductionDB: Float {
        switch self {
        case .off: return 0
        case .light: return -12
        case .medium: return -24
        case .strong: return -40
        }
    }
}
