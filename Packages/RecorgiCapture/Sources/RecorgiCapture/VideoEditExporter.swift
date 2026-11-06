import AVFoundation
import Foundation
import RecorgiCore

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
    ///   - microphoneVolume: applied to the microphone track when the
    ///     source has two separate audio tracks (see `buildAudioMix`'s own
    ///     doc comment on how that's decided). Ignored otherwise.
    ///   - systemAudioVolume: same, for the system-audio track.
    ///   - combinedVolume: applied instead of the two above when the source
    ///     has only one audio track (mic and system audio already mixed
    ///     together, or only one of them was ever captured).
    ///   - microphoneNoiseSuppression: gates down the microphone track's
    ///     background noise (see `MicrophoneNoiseSuppressor`'s doc comment).
    ///     Only takes effect when the source has two separate audio tracks,
    ///     same restriction as microphoneVolume/systemAudioVolume.
    ///   - onProgress: called with a 0...1 fraction on the main actor.
    public func export(
        sourceURL: URL,
        range: CMTimeRange,
        speed: Double,
        microphoneVolume: AudioTrackVolume = AudioTrackVolume(),
        systemAudioVolume: AudioTrackVolume = AudioTrackVolume(),
        combinedVolume: AudioTrackVolume = AudioTrackVolume(),
        microphoneNoiseSuppression: NoiseSuppressionLevel = .off,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        Log.library.notice("export(): starting, range=\(range.duration.seconds, privacy: .public)s speed=\(speed, privacy: .public)x source=\(sourceURL.lastPathComponent, privacy: .public)")

        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            Log.library.error("export(): source has no video track")
            throw VideoEditError.noVideoTrack
        }

        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        try compositionVideoTrack?.insertTimeRange(range, of: sourceVideoTrack, at: .zero)
        if let transform = try? await sourceVideoTrack.load(.preferredTransform) {
            compositionVideoTrack?.preferredTransform = transform
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var compositionAudioTracks: [AVMutableCompositionTrack] = []
        for sourceAudioTrack in audioTracks {
            let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try? compositionAudioTrack?.insertTimeRange(range, of: sourceAudioTrack, at: .zero)
            if let compositionAudioTrack {
                compositionAudioTracks.append(compositionAudioTrack)
            }
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
            Log.library.error("export(): AVAssetExportSession init failed")
            throw VideoEditError.exportSetupFailed
        }

        // Region times are expressed in source-recording seconds (same
        // coordinate space as the trim scrubber the editor builds them
        // against); the composition's own timeline starts at zero at
        // `range.start` and is additionally scaled by `speed` — both
        // accounted for inside buildAudioMix.
        exportSession.audioMix = Self.buildAudioMix(
            tracks: compositionAudioTracks,
            microphoneVolume: microphoneVolume,
            systemAudioVolume: systemAudioVolume,
            combinedVolume: combinedVolume,
            microphoneNoiseSuppression: microphoneNoiseSuppression,
            sourceRangeStart: range.start.seconds,
            speed: speed
        )
        Log.library.notice("export(): mixing \(compositionAudioTracks.count, privacy: .public) source audio tracks into playback copy; original preserved")

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
            Log.library.notice("export(): ok -> \(outputURL.lastPathComponent, privacy: .public)")
        } catch {
            Log.library.error("export(): failed: \(error.localizedDescription, privacy: .public)")
            throw VideoEditError.exportFailed(error.localizedDescription)
        }

        return outputURL
    }

    /// Builds the AVMutableAudioMix shared by both live preview (called
    /// against the source asset's own tracks, `sourceRangeStart: 0, speed:
    /// 1`) and export (called against the composition's tracks, with the
    /// actual trim/speed applied) — same model, same result either way, so
    /// what's heard while editing matches what gets saved.
    ///
    /// Track identity: when there are two audio tracks, index 0 is system
    /// audio and index 1 is the microphone. That order isn't documented by
    /// ScreenCaptureKit anywhere — it was confirmed empirically (silence
    /// pattern and start-time offset of a real two-source test recording:
    /// the microphone track has a continuously present noise floor and
    /// starts a beat later, matching real hardware activation lag; the
    /// system-audio track is true digital silence outside the clip that
    /// was actually playing, and starts within a few milliseconds of the
    /// video track). Re-verify if this ever stops holding. A single-track
    /// source (older macOS, or only one of the two was ever captured) uses
    /// `combinedVolume` instead, since there's nothing to tell apart.
    ///
    /// Overlapping or directly-adjacent regions on the same track aren't
    /// specially reconciled — each region restores the track's base gain
    /// at its own end, so two regions sharing an exact boundary can race;
    /// not worth the complexity for what should be a rare edit.
    public static func buildAudioMix(
        tracks: [AVAssetTrack],
        microphoneVolume: AudioTrackVolume,
        systemAudioVolume: AudioTrackVolume,
        combinedVolume: AudioTrackVolume,
        microphoneNoiseSuppression: NoiseSuppressionLevel = .off,
        sourceRangeStart: Double = 0,
        speed: Double = 1.0
    ) -> AVMutableAudioMix? {
        guard !tracks.isEmpty else { return nil }

        let volumesByTrack: [AudioTrackVolume] = tracks.count == 1
            ? [combinedVolume]
            : [systemAudioVolume, microphoneVolume]
        // Index 1 is the microphone only in the two-track (separate) case —
        // see this function's own doc comment on track identity. A
        // combined track would also carry system audio, so gating it isn't
        // offered.
        let microphoneTrackIndex = tracks.count == 2 ? 1 : nil

        var allParams: [AVMutableAudioMixInputParameters] = []
        var hasAnyAdjustment = false

        for (index, track) in tracks.enumerated() {
            let volume = index < volumesByTrack.count ? volumesByTrack[index] : AudioTrackVolume()
            let params = AVMutableAudioMixInputParameters(track: track)
            params.setVolume(Float(volume.baseGain), at: .zero)
            if volume.baseGain != 1.0 {
                hasAnyAdjustment = true
            }

            if index == microphoneTrackIndex, let tap = MicrophoneNoiseSuppressor.makeTap(level: microphoneNoiseSuppression) {
                params.audioTapProcessor = tap
                hasAnyAdjustment = true
            }

            for region in volume.regions.sorted(by: { $0.startSeconds < $1.startSeconds }) {
                let start = max(0, (region.startSeconds - sourceRangeStart) / speed)
                let end = max(0, (region.endSeconds - sourceRangeStart) / speed)
                guard end > start else { continue }
                let timeRange = CMTimeRange(
                    start: CMTime(seconds: start, preferredTimescale: 600),
                    end: CMTime(seconds: end, preferredTimescale: 600)
                )
                params.setVolumeRamp(fromStartVolume: Float(region.gain), toEndVolume: Float(region.gain), timeRange: timeRange)
                // Restore the track's base gain right after the region ends
                // — otherwise AVAudioMix would hold the region's gain for
                // the rest of the track instead of snapping back.
                params.setVolume(Float(volume.baseGain), at: timeRange.end)
                hasAnyAdjustment = true
            }

            allParams.append(params)
        }

        // Even unity gain needs an explicit mix for separate sources:
        // otherwise playback/export can select just one audio track.
        guard hasAnyAdjustment || tracks.count > 1 else { return nil }

        let mix = AVMutableAudioMix()
        mix.inputParameters = allParams
        return mix
    }

    private static func timestampSuffix() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH.mm.ss"
        return formatter.string(from: Date())
    }
}
