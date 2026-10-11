/// Neither recording path exposes an actual bitrate/compression knob —
/// SCRecordingOutputConfiguration and SCStreamConfiguration have no such
/// property at all, and the legacy path's own bitrate is just computed
/// proportionally to resolution already. Resolution and frame rate are the
/// one thing both paths genuinely share and that we fully control
/// ourselves, so that's what this actually adjusts — lower either one and
/// the file gets smaller the same way a lower bitrate would, just via
/// downscaling instead of an explicit encoder target.
///
/// `.high`'s 1920px/30fps is the existing, already-proven-stable ceiling
/// (see ScreenRecordingEngine's doc comment on real-time H.264 encoding) —
/// deliberately not raised further here.
public enum RecordingQuality: String, CaseIterable, Sendable {
    case high, medium, compact

    public var label: String {
        switch self {
        case .high: return "Высокое"
        case .medium: return "Среднее"
        case .compact: return "Компактное"
        }
    }

    public var detail: String {
        "\(maxDimension)p · \(frameRate) fps"
    }

    /// Cap on the longer edge of the encoded video, in pixels.
    public var maxDimension: Int {
        switch self {
        case .high: return 1920
        case .medium: return 1440
        case .compact: return 1280
        }
    }

    public var frameRate: Int {
        switch self {
        case .high: return 30
        case .medium: return 30
        case .compact: return 24
        }
    }
}
