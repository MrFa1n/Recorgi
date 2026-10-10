import Foundation
import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import Combine
import RecorgiCore

public enum RecordingError: LocalizedError {
    case noDisplayAvailable
    case windowUnavailable
    case noMicrophoneAvailable
    case microphoneSetupFailed
    case audioApplicationUnavailable
    case writerSetupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noDisplayAvailable: return "No display available to record."
        case .windowUnavailable: return "The selected window is no longer available to record."
        case .noMicrophoneAvailable: return "No microphone available."
        case .microphoneSetupFailed: return "Could not set up the microphone input."
        case .audioApplicationUnavailable: return "The selected app is no longer available to capture audio from."
        case .writerSetupFailed(let reason): return "Could not start writing the recording: \(reason)"
        }
    }
}

/// Captures the main display plus, independently, system audio (via
/// ScreenCaptureKit, no virtual-audio-device required) and the microphone
/// (via a plain AVCaptureSession), muxing all of it into one .mov with the
/// video on one track and each enabled audio source on its own track.
@MainActor
public final class ScreenRecordingEngine: NSObject, ObservableObject {
    @Published public private(set) var state: RecordingState = .idle
    @Published public private(set) var lastError: String?

    private var stream: SCStream?
    private var appAudioStream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?

    private var microphoneSession: AVCaptureSession?
    private var microphoneRelay: MicrophoneSampleRelay?
    private let microphoneQueue = DispatchQueue(label: "com.recorgi.microphone-output")

    /// Keeps a visible border around the capture area for the whole
    /// recording, so there's always a reminder of the exact boundary —
    /// excluded from the capture itself (see .area case below).
    private let areaHighlighter = AreaHighlighter()

    public override init() {
        super.init()
    }

    public func start(settings: RecordingSettings) async throws {
        guard case .idle = state else { return }
        // Claimed immediately, before any `await` — start() does a lot of
        // asynchronous work (fetching shareable content, starting streams),
        // and state stayed .idle for the whole duration of that previously.
        // A second tap on Record during that window re-entered this same
        // function, which silently overwrote assetWriter/videoInput/stream
        // etc. out from under the first, still-running call — orphaning its
        // writer mid-write with nothing left to ever call finishWriting() on
        // it. That produced exactly the "no moov atom" unplayable files:
        // no error anywhere, because nothing ever got the chance to fail.
        state = .starting
        lastError = nil

        do {
            try await performStart(settings: settings)
        } catch {
            state = .idle
            throw error
        }
    }

    private func performStart(settings: RecordingSettings) async throws {
        videoFrameCount = 0
        droppedNotReadyCount = 0
        isHandlingWriterFailure = false
        lastVideoPTS = nil
        lastSystemAudioPTS = nil
        lastMicrophonePTS = nil

        try FileManager.default.createDirectory(at: settings.saveDirectory, withIntermediateDirectories: true)
        DebugLog.fileURL = settings.saveDirectory.appendingPathComponent("recorgi-debug.log")
        let fileURL = settings.saveDirectory.appendingPathComponent(Self.timestampedFilename())
        DebugLog.write("=== start: region=\(settings.captureRegion) sysAudio=\(settings.isSystemAudioEnabled) scope=\(settings.systemAudioScope) mic=\(settings.isMicrophoneEnabled) file=\(fileURL.lastPathComponent)")
        let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)

        // Show the highlight border (if applicable) before fetching
        // shareable content, so our own window already exists and can be
        // matched + excluded from the capture filter below.
        if case .area(let info, let rect) = settings.captureRegion {
            areaHighlighter.show(on: info.displayID, rect: rect)
        } else {
            areaHighlighter.hide()
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let primaryDisplay = content.displays.first else {
            throw RecordingError.noDisplayAvailable
        }

        let isAppScoped: Bool
        if case .application = settings.systemAudioScope {
            isAppScoped = true
        } else {
            isAppScoped = false
        }
        let capturesWholeSystemAudio = settings.isSystemAudioEnabled && !isAppScoped

        let filter: SCContentFilter
        let pixelWidth: Int
        let pixelHeight: Int
        var sourceRect: CGRect?

        switch settings.captureRegion {
        case .primaryDisplay:
            filter = SCContentFilter(display: primaryDisplay, excludingWindows: [])
            let scale = Self.backingScaleFactor(for: primaryDisplay.displayID)
            pixelWidth = Self.evenified(Double(primaryDisplay.width) * scale)
            pixelHeight = Self.evenified(Double(primaryDisplay.height) * scale)

        case .display(let info):
            let display = content.displays.first(where: { $0.displayID == info.displayID }) ?? primaryDisplay
            filter = SCContentFilter(display: display, excludingWindows: [])
            let scale = Self.backingScaleFactor(for: display.displayID)
            pixelWidth = Self.evenified(Double(display.width) * scale)
            pixelHeight = Self.evenified(Double(display.height) * scale)

        case .window(let info):
            guard let window = content.windows.first(where: { $0.windowID == info.windowID }) else {
                throw RecordingError.windowUnavailable
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            pixelWidth = Self.evenified(window.frame.width * scale)
            pixelHeight = Self.evenified(window.frame.height * scale)

        case .area(let info, let rect):
            let display = content.displays.first(where: { $0.displayID == info.displayID }) ?? primaryDisplay
            var excludedWindows: [SCWindow] = []
            if let highlightID = areaHighlighter.highlightedWindowID,
               let ownWindow = content.windows.first(where: { $0.windowID == highlightID }) {
                excludedWindows = [ownWindow]
            }
            filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let scale = Self.backingScaleFactor(for: display.displayID)
            pixelWidth = Self.evenified(rect.width * scale)
            pixelHeight = Self.evenified(rect.height * scale)
            sourceRect = rect
        }

        // Uncapped, SCStream delivers frames as fast as the display refreshes
        // (120Hz on ProMotion) at full resolution — a real-time H.264 encode
        // session can't sustain that data rate and fails outright partway
        // in (reproducibly ~1 second in at full-display resolution; small
        // area captures stayed under the threshold, which is why only those
        // worked). 30fps is plenty for screen recording and well within
        // what the encoder can sustain continuously.
        let frameRate = 30

        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = true
        config.capturesAudio = capturesWholeSystemAudio
        config.sampleRate = 48_000
        config.channelCount = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        if let sourceRect {
            config.sourceRect = sourceRect
            config.destinationRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        }

        // Also stop leaving the bitrate to AVFoundation's automatic guess —
        // for a 3024x1964 real-time capture that guess can land somewhere
        // the encoder can't sustain either. Scaled from a known-reasonable
        // 8 Mbps at 1080p30.
        let estimatedBitRate = Int((Double(pixelWidth * pixelHeight) / (1920.0 * 1080.0)) * 8_000_000)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: estimatedBitRate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: frameRate
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)
        self.videoInput = videoInput

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2
        ]

        if settings.isSystemAudioEnabled {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            self.systemAudioInput = input
        }

        if settings.isMicrophoneEnabled {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            self.microphoneInput = input
            try setUpMicrophoneCapture(
                deviceID: settings.selectedMicrophoneID,
                monitoringEnabled: settings.isMonitoringEnabled,
                monitoringOutputID: settings.selectedMonitoringOutputID
            )
        }

        self.assetWriter = writer

        // Start the writer session explicitly, anchored to the current host
        // time, *before* any capture begins — rather than lazily on
        // whichever sample happens to arrive first. Video (ScreenCaptureKit)
        // and microphone audio (AVCaptureSession) are two independent
        // pipelines; letting "whichever fires first" pick the session's zero
        // point made the choice a race, and timestamps from the losing
        // pipeline could land outside what the writer considered valid,
        // silently dropping samples — or worse. Every sample from every
        // source is guaranteed to land at or after a time we captured
        // ourselves, right here.
        guard writer.startWriting() else {
            DebugLog.write("writer.startWriting() FAILED: \(Self.errorDetails(writer.error))")
            throw RecordingError.writerSetupFailed(writer.error?.localizedDescription ?? "unknown error")
        }
        writer.startSession(atSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))
        DebugLog.write("writer.startWriting() ok, pixelSize=\(pixelWidth)x\(pixelHeight), status=\(writer.status.rawValue)")

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        if capturesWholeSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
        }
        try await stream.startCapture()
        self.stream = stream
        DebugLog.write("stream.startCapture() ok")

        if settings.isSystemAudioEnabled, case .application(let app) = settings.systemAudioScope {
            guard let match = content.applications.first(where: { $0.processID == app.processID }) else {
                throw RecordingError.audioApplicationUnavailable
            }
            let appFilter = SCContentFilter(display: primaryDisplay, including: [match], exceptingWindows: [])
            let appConfig = SCStreamConfiguration()
            // We only want this stream's audio; keep its video output tiny
            // since we never register a .screen handler for it.
            appConfig.width = 2
            appConfig.height = 2
            appConfig.capturesAudio = true
            appConfig.sampleRate = 48_000
            appConfig.channelCount = 2

            let appStream = SCStream(filter: appFilter, configuration: appConfig, delegate: self)
            try appStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
            try await appStream.startCapture()
            self.appAudioStream = appStream
        }

        microphoneSession?.startRunning()
        DebugLog.write("mic session started (enabled=\(settings.isMicrophoneEnabled)); state -> recording")
        state = .recording(startedAt: Date())
    }

    public func stop() async {
        guard case .recording = state else {
            DebugLog.write("stop() called but state is \(state) — ignored")
            return
        }
        DebugLog.write("stop() called, writer.status=\(assetWriter?.status.rawValue.description ?? "nil")")
        state = .stopping

        microphoneSession?.stopRunning()
        microphoneSession = nil
        microphoneRelay = nil

        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil

        if let appAudioStream {
            try? await appAudioStream.stopCapture()
        }
        appAudioStream = nil

        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()

        if let writer = assetWriter {
            switch writer.status {
            case .writing:
                await writer.finishWriting()
                DebugLog.write("finishWriting() returned, status=\(writer.status.rawValue) error=\(Self.errorDetails(writer.error))")
                if writer.status == .failed {
                    lastError = writer.error?.localizedDescription ?? "Recording failed to finalize."
                }
            case .failed:
                // The writer can fail *during* capture (an append() call
                // hitting a real encoder/format error), not just when
                // finishWriting() is called — the old `writer.status ==
                // .writing` guard only checked the latter, so a writer that
                // had already died mid-recording was silently skipped here:
                // no finishWriting() call, no error, just an abandoned file
                // with no moov atom. This branch is what actually surfaces
                // that failure now.
                DebugLog.write("writer already .failed at stop() time, error=\(Self.errorDetails(writer.error))")
                lastError = writer.error?.localizedDescription ?? "Recording failed while writing."
            case .cancelled, .completed, .unknown:
                DebugLog.write("writer status at stop() time: \(writer.status.rawValue) (no action)")
            @unknown default:
                break
            }
        }
        assetWriter = nil
        videoInput = nil
        systemAudioInput = nil
        microphoneInput = nil

        areaHighlighter.hide()

        // The hardware H.264 encoder session VideoToolbox hands AVAssetWriter
        // doesn't always finish releasing the instant stopCapture()/
        // finishWriting() return. recorgi-debug.log shows the pipeline itself
        // is sound now (PTS fix made the *first* recording per app launch
        // finish cleanly every time) — but the second and third recordings in
        // the same run die mid-stream at a different, unpredictable frame
        // count with AVFoundationErrorDomain -11800 wrapping OSStatus -16122,
        // which is exactly the signature of the next encode session claiming
        // the hardware encoder before the previous one actually let go. A
        // short cooldown here, before state goes back to .idle and a new
        // recording is allowed to start, gives it that time.
        try? await Task.sleep(nanoseconds: 700_000_000)

        state = .idle
    }

    private func setUpMicrophoneCapture(deviceID: String?, monitoringEnabled: Bool, monitoringOutputID: String?) throws {
        let session = AVCaptureSession()

        let device: AVCaptureDevice?
        if let deviceID, let match = AVCaptureDevice(uniqueID: deviceID) {
            device = match
        } else {
            device = AVCaptureDevice.default(for: .audio)
        }
        guard let device else { throw RecordingError.noMicrophoneAvailable }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw RecordingError.microphoneSetupFailed }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        let relay = MicrophoneSampleRelay { [weak self] sampleBuffer in
            // CMSampleBuffer isn't marked Sendable, but it's just a CF
            // object — safely transferable between threads for this handoff
            // from the microphone queue to the main actor.
            let boxed = SendableSampleBuffer(buffer: sampleBuffer)
            Task { @MainActor [weak self] in
                self?.append(boxed.buffer, to: .microphone)
            }
        }
        output.setSampleBufferDelegate(relay, queue: microphoneQueue)
        guard session.canAddOutput(output) else { throw RecordingError.microphoneSetupFailed }
        session.addOutput(output)

        // Monitoring is purely a live-listen path — it does not touch
        // anything that gets written to the recorded file.
        if monitoringEnabled {
            let preview = AVCaptureAudioPreviewOutput()
            preview.outputDeviceUniqueID = monitoringOutputID
            if session.canAddOutput(preview) {
                session.addOutput(preview)
            }
        }

        self.microphoneSession = session
        self.microphoneRelay = relay
    }

    private enum TrackKind {
        case video, systemAudio, microphone
    }

    private var videoFrameCount = 0
    private var droppedNotReadyCount = 0

    // Video (ScreenCaptureKit) and microphone (AVCaptureSession) are two
    // genuinely independent capture pipelines with their own clocks and
    // buffering/jitter characteristics. AVAssetWriter's real-time
    // multiplexer requires each track's presentation timestamps to be
    // strictly increasing — a single out-of-order sample (accumulated
    // clock drift between the two pipelines is enough, given a few
    // seconds) fails the *entire* writer outright, not just that track.
    // This is a documented failure mode for exactly this ScreenCaptureKit
    // + AVAssetWriter combination; tracking the last PTS per track and
    // dropping anything that doesn't advance is the standard fix.
    private var lastVideoPTS: CMTime?
    private var lastSystemAudioPTS: CMTime?
    private var lastMicrophonePTS: CMTime?

    private func append(_ sampleBuffer: CMSampleBuffer, to track: TrackKind) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            DebugLog.write("append(\(track)): sample not ready, skipped")
            return
        }

        // The writer can die mid-recording (an append() hitting a real
        // encoder/format error) well before anyone presses Stop. Catch that
        // here instead of silently continuing to "record" into a dead
        // writer until the user eventually stops it themselves.
        if assetWriter?.status == .failed {
            handleWriterFailure()
            return
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        switch track {
        case .video:
            guard let videoInput else { return }
            if let last = lastVideoPTS, pts <= last {
                DebugLog.write("dropped non-monotonic video frame: pts=\(pts.seconds) <= last=\(last.seconds)")
                return
            }
            if videoInput.isReadyForMoreMediaData {
                let ok = videoInput.append(sampleBuffer)
                videoFrameCount += 1
                if ok {
                    lastVideoPTS = pts
                    if videoFrameCount == 1 || videoFrameCount % 60 == 0 {
                        DebugLog.write("video frame #\(videoFrameCount) appended ok")
                    }
                } else {
                    DebugLog.write("videoInput.append() returned FALSE at frame \(videoFrameCount), writer.status=\(assetWriter?.status.rawValue ?? -1) error=\(Self.errorDetails(assetWriter?.error))")
                }
            } else {
                droppedNotReadyCount += 1
                if droppedNotReadyCount == 1 || droppedNotReadyCount % 30 == 0 {
                    DebugLog.write("video frame dropped, not ready (count=\(droppedNotReadyCount))")
                }
            }
        case .systemAudio:
            if let last = lastSystemAudioPTS, pts <= last {
                return
            }
            if systemAudioInput?.isReadyForMoreMediaData == true {
                if systemAudioInput?.append(sampleBuffer) == true {
                    lastSystemAudioPTS = pts
                }
            }
        case .microphone:
            if let last = lastMicrophonePTS, pts <= last {
                DebugLog.write("dropped non-monotonic microphone sample: pts=\(pts.seconds) <= last=\(last.seconds)")
                return
            }
            if microphoneInput?.isReadyForMoreMediaData == true {
                if microphoneInput?.append(sampleBuffer) == true {
                    lastMicrophonePTS = pts
                }
            }
        }
    }

    private var isHandlingWriterFailure = false

    private func handleWriterFailure() {
        guard case .recording = state, !isHandlingWriterFailure else { return }
        isHandlingWriterFailure = true
        let message = assetWriter?.error?.localizedDescription ?? "Recording failed while writing."
        DebugLog.write("handleWriterFailure() triggered from append(): \(Self.errorDetails(assetWriter?.error))")
        lastError = message
        Task {
            await stop()
            isHandlingWriterFailure = false
        }
    }

    /// H.264 needs even width/height (4:2:0 chroma subsampling) — a free-
    /// form window size or dragged area almost never lands on one naturally.
    private static func evenified(_ value: Double) -> Int {
        let rounded = Int(value)
        return rounded - (rounded % 2)
    }

    private static func backingScaleFactor(for displayID: CGDirectDisplayID) -> Double {
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               CGDirectDisplayID(number.uint32Value) == displayID {
                return screen.backingScaleFactor
            }
        }
        return 2
    }

    /// `localizedDescription` alone is often a useless generic string
    /// ("The operation could not be completed") — domain/code/userInfo is
    /// what actually identifies the underlying failure.
    private static func errorDetails(_ error: Error?) -> String {
        guard let error else { return "nil" }
        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription) userInfo=\(nsError.userInfo)"
    }

    private static func timestampedFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Recorgi \(formatter.string(from: Date())).mov"
    }
}

extension ScreenRecordingEngine: SCStreamOutput, SCStreamDelegate {
    // Both requirements are nonisolated protocol methods, but SCStream
    // already delivers them on the main queue (sampleHandlerQueue: .main),
    // so we're really always on the main actor here — assumeIsolated makes
    // that known to the compiler instead of hopping through a Task, which
    // would require CMSampleBuffer to be Sendable (it isn't annotated as
    // such, even though it's safe to use this way).
    nonisolated public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let boxed = SendableSampleBuffer(buffer: sampleBuffer)
        MainActor.assumeIsolated {
            switch type {
            case .screen:
                self.append(boxed.buffer, to: .video)
            case .audio:
                self.append(boxed.buffer, to: .systemAudio)
            case .microphone:
                // Newer SDKs can capture the microphone through
                // ScreenCaptureKit itself; we still use our own
                // AVCaptureSession mic path below, so ignore this case.
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated public func stream(_ stream: SCStream, didStopWithError error: Error) {
        MainActor.assumeIsolated {
            DebugLog.write("SCStream didStopWithError: \(error)")
            self.lastError = error.localizedDescription
        }
        Task { await self.stop() }
    }
}

private final class MicrophoneSampleRelay: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        handler(sampleBuffer)
    }
}

/// CMSampleBuffer isn't Sendable in the SDK's annotations, but it's an
/// immutable-enough CF object for a simple cross-queue handoff like ours.
private struct SendableSampleBuffer: @unchecked Sendable {
    let buffer: CMSampleBuffer
}
