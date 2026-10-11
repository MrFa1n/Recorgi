/// Which video codec SCRecordingOutput (or the legacy AVAssetWriter path)
/// encodes the capture with. Framework-free like the rest of RecorgiCore —
/// the actual AVFoundation `AVVideoCodecType` mapping lives in RecorgiCapture.
public enum VideoCodec: String, CaseIterable, Sendable {
    case h264, hevc

    public var label: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC (H.265)"
        }
    }

    public var detail: String {
        switch self {
        case .h264: return "Шире совместимость"
        case .hevc: return "Меньше размер файла"
        }
    }
}
