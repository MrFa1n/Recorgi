/// Which container (file format) the recording is written into. Framework-
/// free like the rest of RecorgiCore — the actual AVFoundation `AVFileType`
/// mapping lives in RecorgiCapture.
public enum VideoContainer: String, CaseIterable, Sendable {
    case mov, mp4

    public var label: String {
        switch self {
        case .mov: return "QuickTime (.mov)"
        case .mp4: return "MPEG-4 (.mp4)"
        }
    }

    /// The filename extension, without the leading dot.
    public var fileExtension: String { rawValue }
}
