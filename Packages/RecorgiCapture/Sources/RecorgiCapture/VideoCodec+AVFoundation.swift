import AVFoundation
import RecorgiCore

public extension VideoCodec {
    var avVideoCodecType: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}

public extension VideoContainer {
    var avFileType: AVFileType {
        switch self {
        case .mov: return .mov
        case .mp4: return .mp4
        }
    }
}
