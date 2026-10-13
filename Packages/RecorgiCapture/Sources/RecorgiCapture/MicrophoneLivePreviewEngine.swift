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
    // var, not let, and rebuilt fresh at the top of every start(): a
    // long-lived AVAudioEngine instance can keep a stale understanding of
    // the hardware input/output format across a device change (e.g.
    // headphones plugged in between a stop() and the next start()) —
    // engine.connect(...) below re-validates against the format it was
    // given, and a mismatch there throws an uncatchable NSException
    // (AVAudioEngine's connect: isn't NSError-based, so Swift's try/catch
    // can't intercept it — reproduced once in testing: SetOutputFormat
    // threw from inside connect() right after a headset was connected).
    // A brand-new engine has no stale state to be wrong about.
    //
    // Deliberately does NOT also observe
    // .AVAudioEngineConfigurationChange to auto-stop on a live device
    // swap — tried that, but the notification also fires ~80ms after a
    // perfectly normal start() (observed with a Bluetooth headset
    // settling into its actual negotiated format), which made the
    // preview toggle look broken far more often than it ever caught a
    // real mid-session device change. The fresh-engine-per-start above is
    // what actually fixes the crash; reacting to every config-change
    // notification was net harmful, not an extra safety net.
    private var engine = AVAudioEngine()
    private let gateContext = NoiseGateContext(level: .off)
    private var sinkNode: AVAudioSinkNode?
    private var sourceNode: AVAudioSourceNode?
    private var ringBuffer: RealtimeFloatRingBuffer?
    // Logs the first sink/source callback after each start() — enough to
    // confirm real audio is actually flowing in both directions without
    // spamming a line per realtime callback (which fires dozens of times
    // a second).
    private var diagnosticsLogger = DiagnosticsLogger()
    public private(set) var isRunning = false
    public private(set) var lastError: String?

    public init() {}

    /// `microphoneDeviceUID`/`outputDeviceUID` nil means "system default" —
    /// same convention as `RecordingSettings.selectedMicrophoneID`/
    /// `selectedMonitoringOutputID`. Calling this while already running
    /// just updates the level (equivalent to calling `setLevel`); switching
    /// devices requires `stop()` first. Returns false (and sets
    /// `lastError`) if the engine couldn't actually start, so the caller
    /// can surface that instead of leaving a toggle on that silently does
    /// nothing.
    @discardableResult
    public func start(microphoneDeviceUID: String?, outputDeviceUID: String?, level: NoiseSuppressionLevel) -> Bool {
        guard !isRunning else {
            setLevel(level)
            return true
        }

        lastError = nil
        gateContext.setLevel(level)
        engine = AVAudioEngine()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        Log.devices.notice("MicrophoneLivePreviewEngine.start: input format sampleRate=\(inputFormat.sampleRate, privacy: .public) channels=\(inputFormat.channelCount, privacy: .public)")
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            lastError = "Микрофон недоступен (пустой входной формат)."
            Log.devices.error("MicrophoneLivePreviewEngine.start: input hardware format unavailable")
            return false
        }

        // Only touch the device explicitly when the caller actually
        // picked a non-default one — the input/output nodes already
        // point at the system default devices on their own, and setting
        // the property redundantly (even to the same device) is an
        // avoidable risk to the unit's already-working configuration.
        if let microphoneDeviceUID, let inputDeviceID = MicrophoneVolumeController.resolveDeviceID(uid: microphoneDeviceUID, isInput: true) {
            Self.setCurrentDevice(inputDeviceID, on: input.audioUnit)
        }
        if let outputDeviceUID, let outputDeviceID = MicrophoneVolumeController.resolveDeviceID(uid: outputDeviceUID, isInput: false) {
            Self.setCurrentDevice(outputDeviceID, on: engine.outputNode.audioUnit)
        }

        let channelCount = Int(inputFormat.channelCount)
        // ~170ms of headroom at 48kHz — comfortably absorbs input/output
        // running on independent IO threads without audible added latency.
        let ring = RealtimeFloatRingBuffer(capacity: 8192 * channelCount)
        ringBuffer = ring
        diagnosticsLogger = DiagnosticsLogger()

        let gateContext = self.gateContext
        let diagnostics = diagnosticsLogger
        // Explicitly @Sendable: without it, Swift infers a closure literal
        // written inside a @MainActor method as isolated to that actor —
        // harmless at compile time, but AVAudioSinkNode actually invokes
        // this block on the realtime CoreAudio IO thread, and the runtime
        // isolation check inserted for that wrong inference crashes with
        // SIGTRAP the first time real audio arrives. @Sendable opts the
        // closure out of that inference; everything it captures
        // (NoiseGateContext, RealtimeFloatRingBuffer, DiagnosticsLogger)
        // is marked Sendable for exactly this reason.
        let sink = AVAudioSinkNode { @Sendable _, _, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
            for buffer in buffers {
                guard let rawData = buffer.mData else { continue }
                let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
                let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = rawData.assumingMemoryBound(to: Float.self)
                diagnostics.logSinkOnce(sampleCount: sampleCount, peak: Self.peakAmplitude(samples, count: sampleCount))
                gateContext.processInPlace(samples: samples, count: sampleCount, channelsInBuffer: channelsInBuffer)
                ring.write(samples, count: sampleCount)
            }
            return noErr
        }
        engine.attach(sink)
        engine.connect(input, to: sink, format: inputFormat)
        sinkNode = sink

        let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: AVAudioChannelCount(channelCount)) ?? inputFormat
        // Same reasoning as the sink's @Sendable above — this one actually
        // crashed in testing before this was added (SIGTRAP from a
        // dispatch_assert_queue failure on the audio IO thread).
        let source = AVAudioSourceNode(format: sourceFormat) { @Sendable isSilence, _, frameCount, outputData in
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
                diagnostics.logSourceOnce(samplesNeeded: samplesNeeded, samplesRead: read)
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
            Log.devices.notice("MicrophoneLivePreviewEngine.start: ok, mic=\(microphoneDeviceUID ?? "<default>", privacy: .public) output=\(outputDeviceUID ?? "<default>", privacy: .public) level=\(level.rawValue, privacy: .public) engineRunning=\(self.engine.isRunning, privacy: .public)")
            return true
        } catch {
            lastError = error.localizedDescription
            Log.devices.error("MicrophoneLivePreviewEngine.start: engine.start() failed: \(error.localizedDescription, privacy: .public)")
            teardown()
            return false
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

    // nonisolated: called from the @Sendable sink closure above, on the
    // realtime audio thread — a @MainActor static func (the default for
    // a static member of a @MainActor class) would hit the exact same
    // isolation-check crash the @Sendable annotations are working around.
    nonisolated private static func peakAmplitude(_ samples: UnsafePointer<Float>, count: Int) -> Float {
        var peak: Float = 0
        for i in 0..<count {
            peak = max(peak, abs(samples[i]))
        }
        return peak
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

/// One-shot logging for the realtime sink/source callbacks — real audio
/// data arriving (or not) is exactly what tells apart "no signal is
/// reaching the gate" from "the gate/ring buffer/output path is the
/// problem", without printing a line per callback.
private final class DiagnosticsLogger: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var loggedSink = false
    private var loggedSource = false

    func logSinkOnce(sampleCount: Int, peak: Float) {
        os_unfair_lock_lock(&lock)
        let shouldLog = !loggedSink
        loggedSink = true
        os_unfair_lock_unlock(&lock)
        guard shouldLog else { return }
        Log.devices.notice("MicrophoneLivePreviewEngine: first sink callback, sampleCount=\(sampleCount, privacy: .public) peak=\(peak, privacy: .public)")
    }

    func logSourceOnce(samplesNeeded: Int, samplesRead: Int) {
        os_unfair_lock_lock(&lock)
        let shouldLog = !loggedSource
        loggedSource = true
        os_unfair_lock_unlock(&lock)
        guard shouldLog else { return }
        Log.devices.notice("MicrophoneLivePreviewEngine: first source callback, samplesNeeded=\(samplesNeeded, privacy: .public) samplesRead=\(samplesRead, privacy: .public)")
    }
}
