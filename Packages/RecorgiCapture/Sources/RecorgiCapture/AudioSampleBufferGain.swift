import AudioToolbox
import CoreMedia
import RecorgiCore

/// Scales a raw-PCM CMSampleBuffer's samples in place by a linear gain.
///
/// Used only by ScreenRecordingEngine's legacy per-app audio pipeline
/// (`systemAudioScope == .application`) to apply live volume/mute to that
/// one app's system audio before it's written to the file. That's the only
/// system-audio case where this app ever sees raw samples at all — the
/// primary whole-system path hands everything to ScreenCaptureKit's own
/// SCRecordingOutput, which owns the file internally (see
/// ScreenRecordingEngine's doc comment).
public enum AudioSampleBufferGain {
    /// `gain` is linear (1.0 = unchanged, 0.0 = silence). A no-op at
    /// `gain == 1.0` so the common case (volume untouched) never even
    /// looks at the buffer's contents.
    public static func apply(_ gain: Float, to sampleBuffer: CMSampleBuffer) {
        guard gain != 1.0, let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else { return }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        // Only succeeds when the block buffer is contiguous, which a
        // freshly-delivered ScreenCaptureKit audio sample always is in
        // practice — a non-contiguous buffer is left untouched rather than
        // risking a copy that silently doesn't propagate back.
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard status == noErr, let dataPointer else {
            Log.capture.error("AudioSampleBufferGain.apply: CMBlockBufferGetDataPointer failed, status=\(status, privacy: .public)")
            return
        }

        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let raw = UnsafeMutableRawPointer(dataPointer)

        switch (isFloat, asbd.mBitsPerChannel) {
        case (true, 32):
            let samples = raw.assumingMemoryBound(to: Float32.self)
            let count = totalLength / MemoryLayout<Float32>.size
            for i in 0..<count { samples[i] *= gain }

        case (false, 16):
            let samples = raw.assumingMemoryBound(to: Int16.self)
            let count = totalLength / MemoryLayout<Int16>.size
            for i in 0..<count {
                let scaled = (Float(samples[i]) * gain).rounded()
                samples[i] = Int16(max(Float(Int16.min), min(Float(Int16.max), scaled)))
            }

        case (false, 32):
            let samples = raw.assumingMemoryBound(to: Int32.self)
            let count = totalLength / MemoryLayout<Int32>.size
            for i in 0..<count {
                let scaled = (Double(samples[i]) * Double(gain)).rounded()
                samples[i] = Int32(max(Double(Int32.min), min(Double(Int32.max), scaled)))
            }

        default:
            Log.capture.error("AudioSampleBufferGain.apply: unhandled PCM format, isFloat=\(isFloat, privacy: .public) bitsPerChannel=\(asbd.mBitsPerChannel, privacy: .public)")
        }
    }
}
