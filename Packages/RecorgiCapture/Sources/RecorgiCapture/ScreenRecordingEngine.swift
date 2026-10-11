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
    case recordingSetupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noDisplayAvailable: return "No display available to record."
        case .windowUnavailable: return "The selected window is no longer available to record."
        case .noMicrophoneAvailable: return "No microphone available."
        case .microphoneSetupFailed: return "Could not set up the microphone input."
        case .audioApplicationUnavailable: return "The selected app is no longer available to capture audio from."
        case .writerSetupFailed(let reason): return "Could not start writing the recording: \(reason)"
        case .recordingSetupFailed(let reason): return "Could not start recording: \(reason)"
        }
    }
}

/// Captures the main display (or a window/area) to a file. The default path
/// hands the whole job — video, system audio, and microphone — to
/// ScreenCaptureKit's own SCRecordingOutput (macOS 15+), which owns its own
/// AVAssetWriter internally and synchronizes all three tracks itself. This
/// replaced an earlier hand-rolled pipeline that manually multiplexed
/// ScreenCaptureKit's video/audio samples and a separate AVCaptureSession's
/// microphone samples into one AVAssetWriter ourselves — two independent
/// capture pipelines with their own clocks were a persistent source of
/// corrupted recordings. The one case SCRecordingOutput can't express —
/// recording a single specific app's system audio while still showing the
/// whole screen — still goes through that manual pipeline (see
/// performStartLegacyAppScopedAudio below).
@MainActor
public final class ScreenRecordingEngine: NSObject, ObservableObject {
    @Published public private(set) var state: RecordingState = .idle
    @Published public private(set) var lastError: String?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var recordingStopContinuation: CheckedContinuation<Void, Never>?

    // Legacy pipeline — only used when systemAudioScope == .application,
    // where SCRecordingOutput can't isolate one app's audio on a stream
    // that's also showing the whole screen.
    private var appAudioStream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?

    // In the primary (SCRecordingOutput) path this session is live
    // monitoring only — ScreenCaptureKit itself captures the microphone
    // into the file via captureMicrophone. In the legacy path it both
    // records and (optionally) monitors.
    private var microphoneSession: AVCaptureSession?
    private var microphoneRelay: MicrophoneSampleRelay?
    private let microphoneQueue = DispatchQueue(label: "com.recorgi.microphone-output")

    /// Keeps a visible border around the capture area for the whole
    /// recording, so there's always a reminder of the exact boundary —
    /// excluded from the capture itself (see .area case below).
    private let areaHighlighter = AreaHighlighter()

    /// Without this, macOS App Nap/idle-throttling can degrade this
    /// process's real-time threads shortly after the window stops being
    /// key/frontmost. ProcessInfo's activity token is Apple's documented
    /// way to tell the OS not to throttle real-time background work like a
    /// recording in progress.
    private var recordingActivityToken: NSObjectProtocol?

    public override init() {
        super.init()
    }

    public func start(settings: RecordingSettings) async throws {
        guard case .idle = state else { return }
        // Claimed immediately, before any `await` — a second tap on Record
        // while setup is still in flight used to re-enter this function and
        // silently overwrite state out from under the first call, orphaning
        // whatever it had already started.
        state = .starting
        lastError = nil

        do {
            try await performStart(settings: settings)
        } catch {
            endRecordingActivity()
            state = .idle
            throw error
        }
    }

    private func performStart(settings: RecordingSettings) async throws {
        recordingActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled, .automaticTerminationDisabled],
            reason: "Screen recording in progress"
        )

        videoFrameCount = 0
        droppedNotReadyCount = 0
        isHandlingWriterFailure = false
        lastVideoPTS = nil
        lastSystemAudioPTS = nil
        lastMicrophonePTS = nil

        try FileManager.default.createDirectory(at: settings.saveDirectory, withIntermediateDirectories: true)
        DebugLog.fileURL = settings.saveDirectory.appendingPathComponent("recorgi-debug.log")
        let fileURL = settings.saveDirectory.appendingPathComponent(Self.timestampedFilename(extension: settings.videoContainer.fileExtension))
        DebugLog.write("=== start: region=\(settings.captureRegion) sysAudio=\(settings.isSystemAudioEnabled) scope=\(settings.systemAudioScope) mic=\(settings.isMicrophoneEnabled) file=\(fileURL.lastPathComponent)")

        // Show the highlight border (if applicable) before fetching
        // shareable content, so our own window already exists and can be
        // matched + excluded from the capture filter below.
        areaHighlighter.setAccentColor(settings.accentColor?.nsColor ?? .controlAccentColor)
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
        let rawPixelWidth: Int
        let rawPixelHeight: Int
        var sourceRect: CGRect?

        switch settings.captureRegion {
        case .primaryDisplay:
            filter = SCContentFilter(display: primaryDisplay, excludingWindows: [])
            let scale = Self.backingScaleFactor(for: primaryDisplay.displayID)
            rawPixelWidth = Self.evenified(Double(primaryDisplay.width) * scale)
            rawPixelHeight = Self.evenified(Double(primaryDisplay.height) * scale)

        case .display(let info):
            let display = content.displays.first(where: { $0.displayID == info.displayID }) ?? primaryDisplay
            filter = SCContentFilter(display: display, excludingWindows: [])
            let scale = Self.backingScaleFactor(for: display.displayID)
            rawPixelWidth = Self.evenified(Double(display.width) * scale)
            rawPixelHeight = Self.evenified(Double(display.height) * scale)

        case .window(let info):
            guard let window = content.windows.first(where: { $0.windowID == info.windowID }) else {
                throw RecordingError.windowUnavailable
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            rawPixelWidth = Self.evenified(window.frame.width * scale)
            rawPixelHeight = Self.evenified(window.frame.height * scale)

        case .area(let info, let rect):
            let display = content.displays.first(where: { $0.displayID == info.displayID }) ?? primaryDisplay
            var excludedWindows: [SCWindow] = []
            if let highlightID = areaHighlighter.highlightedWindowID,
               let ownWindow = content.windows.first(where: { $0.windowID == highlightID }) {
                excludedWindows = [ownWindow]
            }
            filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            // Deliberately *not* multiplying by backingScaleFactor here like
            // the other cases do: a destinationRect sized larger than
            // sourceRect forces ScreenCaptureKit to resize every frame, not
            // just crop it, and an isolated repeat test (RECORGI_STRESS_ONLY
            // =smallarea, fresh process each time) showed video reliably
            // stopping at frame 17 whenever that resize was in play —
            // reproduced identically under both the old manual pipeline and
            // the new SCRecordingOutput one, so the resize step itself is
            // the trigger. Keeping destinationRect the same size as
            // sourceRect makes this a pure crop, which is stable.
            rawPixelWidth = Self.evenified(rect.width)
            rawPixelHeight = Self.evenified(rect.height)
            sourceRect = rect
        }

        // Cap the encode resolution on the longer edge, per the chosen
        // RecordingQuality — keeps real-time H.264/HEVC encoding
        // comfortably sustainable regardless of the physical display's
        // native (often Retina) resolution. .high's 1920 is the original,
        // already-proven-stable ceiling; the lower presets only ever go
        // smaller, never above it.
        let maxDimension = Double(settings.recordingQuality.maxDimension)
        let longerEdge = Double(max(rawPixelWidth, rawPixelHeight))
        let downscale = longerEdge > maxDimension ? maxDimension / longerEdge : 1.0
        let pixelWidth = Self.evenified(Double(rawPixelWidth) * downscale)
        let pixelHeight = Self.evenified(Double(rawPixelHeight) * downscale)

        // SCStream delivers frames as fast as the display refreshes (120Hz
        // on ProMotion) unless capped — the chosen RecordingQuality's frame
        // rate is always comfortably within what the encoder can sustain
        // continuously at the resolution above.
        let frameRate = settings.recordingQuality.frameRate

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

        if isAppScoped {
            try await performStartLegacyAppScopedAudio(
                settings: settings,
                content: content,
                primaryDisplay: primaryDisplay,
                filter: filter,
                config: config,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                frameRate: frameRate,
                fileURL: fileURL
            )
        } else {
            try await performStartRecordingOutput(
                settings: settings,
                filter: filter,
                config: config,
                fileURL: fileURL
            )
        }
    }

    /// The default, robust path: ScreenCaptureKit owns the whole file —
    /// video, system audio, and microphone all synchronized internally by
    /// SCRecordingOutput. No manual sample handling, no PTS bookkeeping.
    private func performStartRecordingOutput(
        settings: RecordingSettings,
        filter: SCContentFilter,
        config: SCStreamConfiguration,
        fileURL: URL
    ) async throws {
        config.captureMicrophone = settings.isMicrophoneEnabled
        if settings.isMicrophoneEnabled, let deviceID = settings.selectedMicrophoneID {
            config.microphoneCaptureDeviceID = deviceID
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)

        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = fileURL
        recordingConfig.outputFileType = settings.videoContainer.avFileType
        recordingConfig.videoCodecType = settings.videoCodec.avVideoCodecType
        let recordingOutput = SCRecordingOutput(configuration: recordingConfig, delegate: self)

        // Must be added before startCapture() to guarantee the first frame
        // lands in the recording.
        try stream.addRecordingOutput(recordingOutput)
        try await stream.startCapture()

        self.stream = stream
        self.recordingOutput = recordingOutput
        DebugLog.write("SCRecordingOutput: stream.startCapture() ok, pixelSize=\(config.width)x\(config.height)")

        if settings.isMicrophoneEnabled, settings.isMonitoringEnabled {
            try setUpMicrophoneMonitoring(
                deviceID: settings.selectedMicrophoneID,
                monitoringOutputID: settings.selectedMonitoringOutputID
            )
            microphoneSession?.startRunning()
        }

        state = .recording(startedAt: Date())
    }

    /// Only reached when systemAudioScope == .application: SCRecordingOutput
    /// can't isolate one app's audio on a stream that's also showing the
    /// whole screen, so this keeps the original manual AVAssetWriter
    /// pipeline (two independent ScreenCaptureKit streams plus a separate
    /// AVCaptureSession for the microphone, muxed by hand with per-track
    /// monotonic-PTS guards).
    private func performStartLegacyAppScopedAudio(
        settings: RecordingSettings,
        content: SCShareableContent,
        primaryDisplay: SCDisplay,
        filter: SCContentFilter,
        config: SCStreamConfiguration,
        pixelWidth: Int,
        pixelHeight: Int,
        frameRate: Int,
        fileURL: URL
    ) async throws {
        let writer = try AVAssetWriter(outputURL: fileURL, fileType: settings.videoContainer.avFileType)

        let estimatedBitRate = Int((Double(pixelWidth * pixelHeight) / (1920.0 * 1080.0)) * 8_000_000)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: settings.videoCodec.avVideoCodecType,
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

        let systemInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        systemInput.expectsMediaDataInRealTime = true
        writer.add(systemInput)
        self.systemAudioInput = systemInput

        if settings.isMicrophoneEnabled {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            self.microphoneInput = input
            try setUpMicrophoneRecording(
                deviceID: settings.selectedMicrophoneID,
                monitoringEnabled: settings.isMonitoringEnabled,
                monitoringOutputID: settings.selectedMonitoringOutputID
            )
        }

        self.assetWriter = writer

        guard writer.startWriting() else {
            DebugLog.write("legacy: writer.startWriting() FAILED: \(Self.errorDetails(writer.error))")
            throw RecordingError.writerSetupFailed(writer.error?.localizedDescription ?? "unknown error")
        }
        writer.startSession(atSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))
        DebugLog.write("legacy: writer.startWriting() ok, pixelSize=\(pixelWidth)x\(pixelHeight), status=\(writer.status.rawValue)")

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        self.stream = stream
        DebugLog.write("legacy: stream.startCapture() ok")

        guard case .application(let app) = settings.systemAudioScope,
              let match = content.applications.first(where: { $0.processID == app.processID }) else {
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

        microphoneSession?.startRunning()
        DebugLog.write("legacy: mic session started (enabled=\(settings.isMicrophoneEnabled)); state -> recording")
        state = .recording(startedAt: Date())
    }

    public func stop() async {
        guard case .recording = state else {
            DebugLog.write("stop() called but state is \(state) — ignored")
            return
        }
        state = .stopping

        microphoneSession?.stopRunning()
        microphoneSession = nil
        microphoneRelay = nil

        if let recordingOutput, let stream {
            DebugLog.write("stop(): removing SCRecordingOutput")
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                recordingStopContinuation = continuation
                do {
                    try stream.removeRecordingOutput(recordingOutput)
                } catch {
                    DebugLog.write("removeRecordingOutput threw: \(Self.errorDetails(error))")
                    lastError = error.localizedDescription
                    recordingStopContinuation = nil
                    continuation.resume()
                }
            }
            self.recordingOutput = nil
        }

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
                // finishWriting() is called — only checking the .writing
                // case here would silently skip surfacing that failure.
                DebugLog.write("legacy: writer already .failed at stop() time, error=\(Self.errorDetails(writer.error))")
                lastError = writer.error?.localizedDescription ?? "Recording failed while writing."
            case .cancelled, .completed, .unknown:
                DebugLog.write("legacy: writer status at stop() time: \(writer.status.rawValue) (no action)")
            @unknown default:
                break
            }
        }
        assetWriter = nil
        videoInput = nil
        systemAudioInput = nil
        microphoneInput = nil

        areaHighlighter.hide()
        endRecordingActivity()

        state = .idle
    }

    private func endRecordingActivity() {
        if let recordingActivityToken {
            ProcessInfo.processInfo.endActivity(recordingActivityToken)
            self.recordingActivityToken = nil
        }
    }

    /// Records the microphone into the file by hand — only used by the
    /// legacy app-scoped-audio path.
    private func setUpMicrophoneRecording(deviceID: String?, monitoringEnabled: Bool, monitoringOutputID: String?) throws {
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

    /// Live-listen only, no recording — used alongside the primary
    /// SCRecordingOutput path, where ScreenCaptureKit itself captures the
    /// microphone straight into the file via captureMicrophone.
    private func setUpMicrophoneMonitoring(deviceID: String?, monitoringOutputID: String?) throws {
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

        let preview = AVCaptureAudioPreviewOutput()
        preview.outputDeviceUniqueID = monitoringOutputID
        guard session.canAddOutput(preview) else { throw RecordingError.microphoneSetupFailed }
        session.addOutput(preview)

        self.microphoneSession = session
    }

    // MARK: - Legacy manual muxing (app-scoped audio only)

    private enum TrackKind {
        case video, systemAudio, microphone
    }

    private var videoFrameCount = 0
    private var droppedNotReadyCount = 0

    // Video (ScreenCaptureKit) and microphone (AVCaptureSession) are two
    // genuinely independent capture pipelines with their own clocks in this
    // legacy path. AVAssetWriter's real-time multiplexer requires each
    // track's presentation timestamps to be strictly increasing — a single
    // out-of-order sample fails the *entire* writer outright, not just that
    // track. Tracking the last PTS per track and dropping anything that
    // doesn't advance is the standard fix.
    private var lastVideoPTS: CMTime?
    private var lastSystemAudioPTS: CMTime?
    private var lastMicrophonePTS: CMTime?

    private func append(_ sampleBuffer: CMSampleBuffer, to track: TrackKind) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

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
            if let last = lastVideoPTS, pts <= last { return }
            if videoInput.isReadyForMoreMediaData {
                let ok = videoInput.append(sampleBuffer)
                videoFrameCount += 1
                if ok {
                    lastVideoPTS = pts
                } else {
                    DebugLog.write("legacy: videoInput.append() returned FALSE at frame \(videoFrameCount), writer.status=\(assetWriter?.status.rawValue ?? -1) error=\(Self.errorDetails(assetWriter?.error))")
                }
            } else {
                droppedNotReadyCount += 1
            }
        case .systemAudio:
            if let last = lastSystemAudioPTS, pts <= last { return }
            if systemAudioInput?.isReadyForMoreMediaData == true {
                if systemAudioInput?.append(sampleBuffer) == true {
                    lastSystemAudioPTS = pts
                }
            }
        case .microphone:
            if let last = lastMicrophonePTS, pts <= last { return }
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
        DebugLog.write("legacy: handleWriterFailure() triggered from append(): \(Self.errorDetails(assetWriter?.error))")
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

    private static func timestampedFilename(extension fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Recorgi \(formatter.string(from: Date())).\(fileExtension)"
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

extension ScreenRecordingEngine: SCRecordingOutputDelegate {
    // SCRecordingOutput doesn't document which queue these land on (unlike
    // SCStreamOutput's explicit sampleHandlerQueue), so hop via Task rather
    // than assuming main-actor isolation here.
    nonisolated public func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            DebugLog.write("SCRecordingOutput: recording started")
        }
    }

    nonisolated public func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            DebugLog.write("SCRecordingOutput: didFailWithError \(Self.errorDetails(error))")
            self.lastError = error.localizedDescription
            self.recordingStopContinuation?.resume()
            self.recordingStopContinuation = nil
        }
    }

    nonisolated public func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            DebugLog.write("SCRecordingOutput: finished recording ok")
            self.recordingStopContinuation?.resume()
            self.recordingStopContinuation = nil
        }
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
