import AVFoundation
import Foundation

public enum VideoEditError: LocalizedError {
    case noVideoTrack
    case exportSetupFailed
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "Не удалось прочитать видеодорожку."
        case .exportSetupFailed: return "Не удалось подготовить экспорт."
        case .exportFailed(let reason): return "Ошибка экспорта: \(reason)"
        }
    }
}

/// Trims and/or speed-changes a recording by building an AVMutableComposition
/// and exporting it to a new file — the in-app editor's "save" action.
/// Never overwrites the original; the source recording is always left
/// untouched.
public struct VideoEditExporter: Sendable {
    public init() {}

    /// - Parameters:
    ///   - range: the time range (within the source) to keep.
    ///   - speed: 1.0 = unchanged, 2.0 = twice as fast, 0.5 = half speed.
    ///   - onProgress: called with a 0...1 fraction on the main actor.
    public func export(
        sourceURL: URL,
        range: CMTimeRange,
        speed: Double,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw VideoEditError.noVideoTrack
        }

        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        try compositionVideoTrack?.insertTimeRange(range, of: sourceVideoTrack, at: .zero)
        if let transform = try? await sourceVideoTrack.load(.preferredTransform) {
            compositionVideoTrack?.preferredTransform = transform
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        for sourceAudioTrack in audioTracks {
            let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try? compositionAudioTrack?.insertTimeRange(range, of: sourceAudioTrack, at: .zero)
        }

        if speed != 1.0 {
            let trimmedRange = CMTimeRange(start: .zero, duration: range.duration)
            let scaledDuration = CMTimeMultiplyByFloat64(range.duration, multiplier: 1.0 / speed)
            composition.scaleTimeRange(trimmedRange, toDuration: scaledDuration)
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let outputURL = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName) (изменено \(Self.timestampSuffix())).mov")

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoEditError.exportSetupFailed
        }

        // AVAssetExportSession isn't Sendable, and Swift 6's region checker
        // can't see that observing .states() concurrently with export(to:)
        // is the API's own intended, safe use (its own export(to:as:)
        // wrapper does the same internally, escaping with
        // nonisolated(unsafe) for exactly this reason) — opt out of the
        // check here rather than fighting it.
        nonisolated(unsafe) let session = exportSession
        if let onProgress {
            Task {
                for await state in session.states(updateInterval: 0.2) {
                    if case .exporting(let progress) = state {
                        await onProgress(progress.fractionCompleted)
                    }
                }
            }
        }

        do {
            try await session.export(to: outputURL, as: .mov)
        } catch {
            throw VideoEditError.exportFailed(error.localizedDescription)
        }

        return outputURL
    }

    private static func timestampSuffix() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH.mm.ss"
        return formatter.string(from: Date())
    }
}
