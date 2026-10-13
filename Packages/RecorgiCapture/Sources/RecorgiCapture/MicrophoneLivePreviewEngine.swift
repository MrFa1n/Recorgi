import AVFoundation
import AudioToolbox
import CoreAudio
import RecorgiCore

/// Lets the user hear their own microphone gated through the exact same
/// noise-suppression algorithm `MicrophoneNoiseSuppressor`/`buildAudioMix`
/// apply at export time (see `NoiseGateContext`, shared by both) — live, so
/// a level can be auditioned before recording starts, and switched on the
/// fly while a recording is already in progress. Switching levels is just
/// a mutation on the shared `NoiseGateContext`; it never tears down or
/// rebuilds the audio graph, so there's no click or dropout.
///
/// This only ever affects what's HEARD. It has no connection to what
/// actually gets written to the recorded file — in the primary recording
/// path the microphone is captured directly by ScreenCaptureKit's own
/// SCRecordingOutput (see `ScreenRecordingEngine`'s doc comment), and this
/// app never sees a raw sample from it while actually recording. The level
/// chosen here only gets baked into the saved file afterwards, in the
/// editor/export step (`RecordingEditorView` starts pre-set to whatever
/// level was last live-previewed, via `RecordingSettings.
/// microphoneNoiseSuppression`).
///
/// Built on an AVAudioEngine sink→ring-buffer→source pipeline rather than a
/// tap, because a tap only observes audio — it can't feed modified samples
/// back into the signal actually reaching the output device. The sink node
/// gates each captured buffer in place and pushes it into a
/// RealtimeFloatRingBuffer; the source node pulls from that buffer to
/// render the output. Input and output run on independent CoreAudio IO
/// threads (potentially different physical devices), which is what the
/// ring buffer is actually for, not just decoration.
@MainActor
public final class MicrophoneLivePreviewEngine {
    private let engine = AVAudioEngine()
    private let gateContext = NoiseGateContext(level: .off)
    private var sinkNode: AVAudioSinkNode?
    private var sourceNode: AVAudioSourceNode?
    private var ringBuffer: RealtimeFloatRingBuffer?
    public private(set) var isRunning = false

    public init() {}

    /// `microphoneDeviceUID`/`outputDeviceUID` nil means "system default" —
    /// same convention as `RecordingSettings.selectedMicrophoneID`/
    /// `selectedMonitoringOutputID`. Calling this while already running
    /// just updates the level (equivalent to calling `setLevel`); switching
    /// devices requires `stop()` first.
    public func start(microphoneDeviceUID: String?, outputDeviceUID: String?, level: NoiseSuppressionLevel) {
        guard !isRunning else {
            setLevel(level)
            return
        }

        gateContext.setLevel(level)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Log.devices.error("MicrophoneLivePreviewEngine.start: input hardware format unavailable")
            return
        }

        if let inputDeviceID = MicrophoneVolumeController.resolveDeviceID(uid: microphoneDeviceUID, isInput: true) {
            Self.setCurrentDevice(inputDeviceID, on: input.audioUnit)
        }
        if let outputDeviceID = MicrophoneVolumeController.resolveDeviceID(uid: outputDeviceUID, isInput: false) {
            Self.setCurrentDevice(outputDeviceID, on: engine.outputNode.audioUnit)
        }

        let channelCount = Int(inputFormat.channelCount)
        // ~170ms of headroom at 48kHz — comfortably absorbs input/output
        // running on independent IO threads without audible added latency.
        let ring = RealtimeFloatRingBuffer(capacity: 8192 * channelCount)
        ringBuffer = ring

        let gateContext = self.gateContext
        let sink = AVAudioSinkNode { _, _, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
            for buffer in buffers {
                guard let rawData = buffer.mData else { continue }
                let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
                let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = rawData.assumingMemoryBound(to: Float.self)
                gateContext.processInPlace(samples: samples, count: sampleCount, channelsInBuffer: channelsInBuffer)
                ring.write(samples, count: sampleCount)
            }
            return noErr
        }
        engine.attach(sink)
        engine.connect(input, to: sink, format: inputFormat)
        sinkNode = sink

        let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: AVAudioChannelCount(channelCount)) ?? inputFormat
        let source = AVAudioSourceNode(format: sourceFormat) { isSilence, _, frameCount, outputData in
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            for buffer in buffers {
                guard let rawData = buffer.mData else { continue }
                let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
                let samplesNeeded = Int(frameCount) * channelsInBuffer
                let out = rawData.assumingMemoryBound(to: Float.self)
                let read = ring.read(into: out, count: samplesNeeded)
                if read < samplesNeeded {
                    for i in read..<samplesNeeded { out[i] = 0 }
                }
            }
            isSilence.pointee = false
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: sourceFormat)
        sourceNode = source

        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            Log.devices.notice("MicrophoneLivePreviewEngine.start: ok, mic=\(microphoneDeviceUID ?? "<default>", privacy: .public) output=\(outputDeviceUID ?? "<default>", privacy: .public) level=\(level.rawValue, privacy: .public)")
        } catch {
            Log.devices.error("MicrophoneLivePreviewEngine.start: engine.start() failed: \(error.localizedDescription, privacy: .public)")
            teardown()
        }
    }

    public func setLevel(_ level: NoiseSuppressionLevel) {
        gateContext.setLevel(level)
    }

    public func stop() {
        guard isRunning else { return }
        Log.devices.notice("MicrophoneLivePreviewEngine.stop")
        teardown()
    }

    private func teardown() {
        engine.stop()
        if let sinkNode {
            engine.disconnectNodeInput(sinkNode)
            engine.detach(sinkNode)
        }
        if let sourceNode {
            engine.disconnectNodeOutput(sourceNode)
            engine.detach(sourceNode)
        }
        sinkNode = nil
        sourceNode = nil
        ringBuffer = nil
        isRunning = false
    }

    private static func setCurrentDevice(_ deviceID: AudioDeviceID, on audioUnit: AudioUnit?) {
        guard let audioUnit else { return }
        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            Log.devices.error("MicrophoneLivePreviewEngine.setCurrentDevice: AudioUnitSetProperty failed, status=\(status, privacy: .public)")
        }
    }
}
