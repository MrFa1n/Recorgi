import Foundation
import CoreMedia
import MediaToolbox
import AudioToolbox
import RecorgiCore

/// How aggressively `MicrophoneNoiseSuppressor` gates down the quiet,
/// background-noise moments of the microphone track. Applied in the in-app
/// editor and at export time only — see `MicrophoneNoiseSuppressor`'s own
/// doc comment for why this can't be done live during recording.
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
    /// background noise and attenuated.
    fileprivate var thresholdDB: Float {
        switch self {
        case .off: return 0
        case .light: return -50
        case .medium: return -42
        case .strong: return -34
        }
    }

    /// How far a fully-gated moment gets attenuated, in dB.
    fileprivate var maxReductionDB: Float {
        switch self {
        case .off: return 0
        case .light: return -12
        case .medium: return -24
        case .strong: return -40
        }
    }
}

/// Gates down the microphone track's background noise via a classic
/// envelope-follower noise gate (soft-knee downward expander) — not ML-based
/// denoising, but a real, tunable reduction that's cheap and predictable.
///
/// This only ever runs as an `MTAudioProcessingTap` plugged into the
/// microphone track's `AVMutableAudioMixInputParameters`, the same mechanism
/// `VideoEditExporter.buildAudioMix` already uses for per-region volume —
/// which is why one implementation covers both the live editor preview
/// (`AVPlayerItem.audioMix`) and the final export (`AVAssetExportSession.
/// audioMix`): both just evaluate the same `AVAudioMix`.
///
/// Why not live, during recording: the primary recording path hands the
/// microphone straight to ScreenCaptureKit's own `SCRecordingOutput` (see
/// `ScreenRecordingEngine`'s doc comment) — this app never sees a single raw
/// microphone sample while actually recording, the same constraint that
/// already ruled out live system-audio volume control. Noise suppression is
/// applied after the fact instead, on whatever track in the finished file
/// turns out to hold the microphone (see `buildAudioMix`'s track-identity
/// doc comment) — which also means it only makes sense when that track is
/// isolated from system audio (two separate tracks, macOS 27+); gating a
/// combined mic+system track would attenuate system-audio content too.
public enum MicrophoneNoiseSuppressor {
    /// Builds a tap for `level`, or nil for `.off` — `.off` means no tap at
    /// all, a hard guarantee the signal passes through completely
    /// untouched rather than a gate configured to do nothing.
    public static func makeTap(level: NoiseSuppressionLevel) -> MTAudioProcessingTap? {
        guard level != .off else { return nil }

        let context = NoiseGateContext(level: level)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(context).toOpaque(),
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<NoiseGateContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, formatPointer in
                let context = Unmanaged<NoiseGateContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                context.prepare(sampleRate: formatPointer.pointee.mSampleRate)
            },
            unprepare: nil,
            process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
                var sourceFlags: MTAudioProcessingTapFlags = 0
                let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, &sourceFlags, nil, numberFramesOut)
                flagsOut.pointee = sourceFlags
                guard status == noErr else { return }
                let context = Unmanaged<NoiseGateContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                context.process(bufferList: bufferListInOut, frameCount: numberFramesOut.pointee)
            }
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        guard status == noErr else {
            Log.library.error("MicrophoneNoiseSuppressor.makeTap: MTAudioProcessingTapCreate failed, status=\(status, privacy: .public)")
            // The retained context above would otherwise leak with nothing
            // left to balance it (finalize never runs if creation failed).
            Unmanaged<NoiseGateContext>.fromOpaque(callbacks.clientInfo!).release()
            return nil
        }
        return tap
    }
}

/// Per-tap mutable state: envelope-follower history (one slot per channel,
/// capped since real microphone tracks never exceed a couple) plus the
/// attack/release coefficients, which depend on the sample rate only known
/// once `prepare` runs.
private final class NoiseGateContext {
    private let thresholdDB: Float
    private let maxReductionDB: Float
    private static let kneeDB: Float = 6
    private static let attackSeconds: Float = 0.005
    private static let releaseSeconds: Float = 0.15
    private static let maxChannels = 8

    private var attackCoeff: Float = 1
    private var releaseCoeff: Float = 1
    private var envelope = [Float](repeating: 0, count: NoiseGateContext.maxChannels)

    init(level: NoiseSuppressionLevel) {
        thresholdDB = level.thresholdDB
        maxReductionDB = level.maxReductionDB
    }

    func prepare(sampleRate: Float64) {
        guard sampleRate > 0 else { return }
        attackCoeff = 1 - exp(-1 / (Float(sampleRate) * Self.attackSeconds))
        releaseCoeff = 1 - exp(-1 / (Float(sampleRate) * Self.releaseSeconds))
        envelope = [Float](repeating: 0, count: Self.maxChannels)
    }

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: CMItemCount) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for buffer in buffers {
            guard let rawData = buffer.mData else { continue }
            let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
            let data = rawData.assumingMemoryBound(to: Float32.self)
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            for i in 0..<sampleCount {
                let channel = i % channelsInBuffer
                let envelopeSlot = channel % Self.maxChannels
                data[i] = gate(sample: data[i], envelopeSlot: envelopeSlot)
            }
        }
    }

    private func gate(sample: Float32, envelopeSlot: Int) -> Float32 {
        let magnitude = abs(sample)
        if magnitude > envelope[envelopeSlot] {
            envelope[envelopeSlot] += attackCoeff * (magnitude - envelope[envelopeSlot])
        } else {
            envelope[envelopeSlot] += releaseCoeff * (magnitude - envelope[envelopeSlot])
        }

        let envelopeDB = 20 * log10(max(envelope[envelopeSlot], 1e-9))
        guard envelopeDB < thresholdDB else { return sample }

        let belowThreshold = thresholdDB - envelopeDB
        let ramp = min(belowThreshold / Self.kneeDB, 1)
        let gainDB = ramp * maxReductionDB
        let gainLinear = pow(10, gainDB / 20)
        return sample * gainLinear
    }
}
