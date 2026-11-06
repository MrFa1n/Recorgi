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

    // Pause/resume support. ScreenCaptureKit has no native pause — the
    // only way to stop producing frames mid-recording is to tear the
    // stream/recording-output down entirely, and the only way to resume
    // is to start a brand new one, which always writes to a brand new
    // file. So a pause/resume cycle produces its own "segment" file;
    // stop() stitches every segment back into one file via
    // AVMutableComposition if there was more than one (see
    // finalizeRecordingSession()). A recording that's never paused is
    // exactly one segment, written directly to `sessionBaseFileURL` —
    // behaves identically to before pause/resume existed.
    private var sessionBaseFileURL: URL?
    private var currentSegmentURL: URL?
    private var segmentURLs: [URL] = []
    private var activeSettings: RecordingSettings?

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
        guard case .idle = state else {
            Log.capture.notice("start() called while state is already \(String(describing: self.state), privacy: .public) — ignored")
            return
        }
        // Claimed immediately, before any `await` — a second tap on Record
        // while setup is still in flight used to re-enter this function and
        // silently overwrite state out from under the first call, orphaning
        // whatever it had already started.
        state = .starting
        lastError = nil
        activeSettings = settings
        segmentURLs = []
        currentSegmentURL = nil

        recordingActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled, .automaticTerminationDisabled],
            reason: "Screen recording in progress"
        )

        // Show the highlight border (if applicable) before fetching
        // shareable content in startSegment(), so our own window already
        // exists and can be matched + excluded from the capture filter.
        // Session-level, not per-segment: stays up across any number of
        // pause/resume cycles, only comes down in finalizeRecordingSession().
        areaHighlighter.setAccentColor(settings.accentColor?.nsColor ?? .controlAccentColor)
        if case .area(let info, let rect) = settings.captureRegion {
            areaHighlighter.show(on: info.displayID, rect: rect)
        } else {
            areaHighlighter.hide()
        }

        do {
            try FileManager.default.createDirectory(at: settings.saveDirectory, withIntermediateDirectories: true)
            let fileURL = settings.saveDirectory.appendingPathComponent(Self.timestampedFilename(extension: settings.videoContainer.fileExtension))
            sessionBaseFileURL = fileURL

            try await startSegment(settings: settings, fileURL: fileURL)
            state = .recording(startedAt: Date())
            Log.capture.info("start() succeeded, state=\(String(describing: self.state), privacy: .public)")
        } catch {
            Log.capture.error("start() failed: \(error.localizedDescription, privacy: .public)")
            areaHighlighter.hide()
            endRecordingActivity()
            activeSettings = nil
            sessionBaseFileURL = nil
            state = .idle
            throw error
        }
    }

    /// Pauses the active recording by tearing down the current segment's
    /// stream/writer entirely — ScreenCaptureKit has no native pause, see
    /// this class's segment-tracking properties for why that forces the
    /// segment-per-pause-cycle design. No-ops (besides a log line) unless
    /// actually recording.
    public func pause() async {
        guard case .recording(let startedAt) = state else {
            Log.capture.notice("pause() called but state is \(String(describing: self.state), privacy: .public) — ignored")
            return
        }
        Log.capture.notice("pause() starting")
        state = .pausing
        await finalizeActiveSegment()
        state = .paused(startedAt: startedAt, pausedAt: Date())
        Log.capture.notice("pause() finished, state=paused, segments=\(self.segmentURLs.count, privacy: .public)")
    }

    /// Resumes a paused recording into a new segment — see `pause()`. On
    /// failure, reverts to `.paused` (rather than `.idle`) so the user can
    /// just try again or still get a valid file by pressing Stop; whatever
    /// was already recorded in earlier segments is never at risk.
    public func resume() async {
        guard case .paused(let startedAt, let pausedAt) = state, let settings = activeSettings else {
            Log.capture.notice("resume() called but state is \(String(describing: self.state), privacy: .public) — ignored")
            return
        }
        guard let fileURL = nextSegmentURL() else {
            Log.capture.error("resume(): no sessionBaseFileURL — can't name the next segment")
            return
        }
        state = .resuming
        do {
            try await startSegment(settings: settings, fileURL: fileURL)
            let pauseDuration = Date().timeIntervalSince(pausedAt)
            state = .recording(startedAt: startedAt.addingTimeInterval(pauseDuration))
            Log.capture.notice("resume() succeeded, segments=\(self.segmentURLs.count + 1, privacy: .public)")
        } catch {
            Log.capture.error("resume() failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            state = .paused(startedAt: startedAt, pausedAt: pausedAt)
        }
    }

    /// Names the file a post-pause segment should write to — always
    /// alongside `sessionBaseFileURL` (where the very first segment
    /// writes directly), never reused across the session, so an earlier
    /// segment is never at risk of being overwritten by a later one.
    private func nextSegmentURL() -> URL? {
        guard let base = sessionBaseFileURL else { return nil }
        let ext = base.pathExtension
        let name = base.deletingPathExtension().lastPathComponent
        return base.deletingLastPathComponent().appendingPathComponent("\(name) (part \(segmentURLs.count + 1)).\(ext)")
    }

    /// Starts one capture segment (the whole recording, if it's never
    /// paused; one slice of it otherwise) — everything that's genuinely
    /// per-segment: computing the capture filter/config fresh, standing up
    /// SCRecordingOutput or the legacy AVAssetWriter pipeline, and pointing
    /// it at `fileURL`. Session-level setup (activity token, area
    /// highlight) happens once in start(), not here, so it survives
    /// however many times this gets called across a session.
    private func startSegment(settings: RecordingSettings, fileURL: URL) async throws {
        videoFrameCount = 0
        droppedNotReadyCount = 0
        isHandlingWriterFailure = false
        lastVideoPTS = nil
        lastSystemAudioPTS = nil
        lastMicrophonePTS = nil
        currentSegmentURL = fileURL

        Log.capture.notice("startSegment: region=\(String(describing: settings.captureRegion), privacy: .public) sysAudio=\(settings.isSystemAudioEnabled, privacy: .public) scope=\(String(describing: settings.systemAudioScope), privacy: .public) mic=\(settings.isMicrophoneEnabled, privacy: .public) codec=\(String(describing: settings.videoCodec), privacy: .public) quality=\(String(describing: settings.recordingQuality), privacy: .public) file=\(fileURL.lastPathComponent, privacy: .public)")

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

        Log.capture.notice("performStart: resolved pixelSize=\(pixelWidth, privacy: .public)x\(pixelHeight, privacy: .public) frameRate=\(frameRate, privacy: .public) pipeline=\(isAppScoped ? "legacy-app-scoped" : "SCRecordingOutput", privacy: .public)")

        // Re-applied here, not just when the user drags the slider in Audio
        // Sources: this is a real CoreAudio hardware setting, so anything
        // else on the system (another app, a device reconnect) could have
        // changed it since. nil means the user never touched the slider —
        // leave the device's existing volume alone.
        if settings.isMicrophoneEnabled, let micVolume = settings.microphoneVolume {
            MicrophoneVolumeController.setVolume(Float(micVolume), deviceUID: settings.selectedMicrophoneID)
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
        // Keep both sources in one playback track. QuickTime may select
        // only one of separate audio tracks, making the microphone appear
        // missing when recording a call. This also matches the mixed output
        // produced on macOS 15–26. Separate editing controls remain useful
        // for older recordings and the app-scoped capture pipeline.
        if #available(macOS 27, *) {
            recordingConfig.mixesAudioWithMicrophone = true
        }
        Log.capture.notice("performStartRecordingOutput: mixed audio output, systemAudio=\(config.capturesAudio, privacy: .public) microphone=\(config.captureMicrophone, privacy: .public) microphoneDevice=\(settings.selectedMicrophoneID ?? "default", privacy: .public)")
        let recordingOutput = SCRecordingOutput(configuration: recordingConfig, delegate: self)

        // Must be added before startCapture() to guarantee the first frame
        // lands in the recording.
        try stream.addRecordingOutput(recordingOutput)
        try await stream.startCapture()

        self.stream = stream
        self.recordingOutput = recordingOutput
        Log.capture.notice("performStartRecordingOutput: stream.startCapture() ok")

        if settings.isMicrophoneEnabled, settings.isMonitoringEnabled {
            try setUpMicrophoneMonitoring(
                deviceID: settings.selectedMicrophoneID,
                monitoringOutputID: settings.selectedMonitoringOutputID
            )
            microphoneSession?.startRunning()
        }
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
            Log.capture.error("performStartLegacyAppScopedAudio: writer.startWriting() FAILED: \(writer.error?.localizedDescription ?? "unknown error", privacy: .public)")
            throw RecordingError.writerSetupFailed(writer.error?.localizedDescription ?? "unknown error")
        }
        writer.startSession(atSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        self.stream = stream

        guard case .application(let app) = settings.systemAudioScope,
              let match = content.applications.first(where: { $0.processID == app.processID }) else {
            Log.capture.error("performStartLegacyAppScopedAudio: target app no longer available")
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
        Log.capture.notice("performStartLegacyAppScopedAudio: both streams started ok, mic=\(settings.isMicrophoneEnabled, privacy: .public)")
    }

    public func stop() async {
        let wasPaused: Bool
        switch state {
        case .recording:
            wasPaused = false
        case .paused:
            wasPaused = true
        default:
            Log.capture.notice("stop() called but state is \(String(describing: self.state), privacy: .public) — ignored")
            return
        }
        Log.capture.notice("stop() starting, wasPaused=\(wasPaused, privacy: .public) segments=\(self.segmentURLs.count, privacy: .public) videoFrames=\(self.videoFrameCount, privacy: .public) droppedNotReady=\(self.droppedNotReadyCount, privacy: .public)")
        state = .stopping

        // Already torn down by pause() if we were paused — nothing active
        // left to finalize, just the merge (if any) below.
        if !wasPaused {
            await finalizeActiveSegment()
        }

        await finalizeRecordingSession()

        state = .idle
        Log.capture.notice("stop() finished, state=idle")
    }

    /// Tears down whichever pipeline (SCRecordingOutput or the legacy
    /// AVAssetWriter) is actively capturing right now, finalizing its
    /// output file and appending it to `segmentURLs`. Shared by pause()
    /// and stop() — the only difference is what happens next: pause()
    /// just stops here, stop() goes on to merge every segment accumulated
    /// so far via finalizeRecordingSession().
    private func finalizeActiveSegment() async {
        microphoneSession?.stopRunning()
        microphoneSession = nil
        microphoneRelay = nil

        if let recordingOutput, let stream {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                recordingStopContinuation = continuation
                do {
                    try stream.removeRecordingOutput(recordingOutput)
                } catch {
                    Log.capture.error("finalizeActiveSegment(): removeRecordingOutput threw: \(error.localizedDescription, privacy: .public)")
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
                Log.capture.notice("finalizeActiveSegment(): legacy writer finishWriting() returned, status=\(writer.status.rawValue, privacy: .public)")
                if writer.status == .failed {
                    Log.capture.error("finalizeActiveSegment(): legacy writer failed to finalize: \(writer.error?.localizedDescription ?? "unknown", privacy: .public)")
                    lastError = writer.error?.localizedDescription ?? "Recording failed to finalize."
                }
            case .failed:
                // The writer can fail *during* capture (an append() call
                // hitting a real encoder/format error), not just when
                // finishWriting() is called — only checking the .writing
                // case here would silently skip surfacing that failure.
                Log.capture.error("finalizeActiveSegment(): legacy writer was already .failed: \(writer.error?.localizedDescription ?? "unknown", privacy: .public)")
                lastError = writer.error?.localizedDescription ?? "Recording failed while writing."
            case .cancelled, .completed, .unknown:
                break
            @unknown default:
                break
            }
        }
        assetWriter = nil
        videoInput = nil
        systemAudioInput = nil
        microphoneInput = nil

        if let currentSegmentURL {
            segmentURLs.append(currentSegmentURL)
            self.currentSegmentURL = nil
        }
    }

    /// Ends the whole user-visible recording session (as opposed to just
    /// one segment): merges every segment pause/resume produced into
    /// `sessionBaseFileURL` if there was more than one, hides the area
    /// highlight, and ends the activity token. A recording that was never
    /// paused has exactly one segment, already sitting at
    /// `sessionBaseFileURL` — nothing to merge, same as before pause/
    /// resume existed.
    private func finalizeRecordingSession() async {
        if segmentURLs.count > 1, let finalURL = sessionBaseFileURL, let settings = activeSettings {
            Log.capture.notice("finalizeRecordingSession: merging \(self.segmentURLs.count, privacy: .public) segments")
            do {
                try await Self.concatenateSegments(segmentURLs, into: finalURL, fileType: settings.videoContainer.avFileType)
                Log.capture.notice("finalizeRecordingSession: merge ok")
            } catch {
                // The individual segment files are left in place (not
                // cleaned up below) specifically so a merge failure never
                // loses anything the user actually recorded — only the
                // convenience of having it as one file.
                Log.capture.error("finalizeRecordingSession: merge failed: \(error.localizedDescription, privacy: .public)")
                lastError = "Не удалось объединить части записи после паузы: \(error.localizedDescription)"
            }
        }

        segmentURLs = []
        currentSegmentURL = nil
        sessionBaseFileURL = nil
        activeSettings = nil

        areaHighlighter.hide()
        endRecordingActivity()
    }

    /// Concatenates `urls` in order into `finalURL` via AVMutableComposition
    /// — the first URL is always `finalURL` itself (segment 1 writes there
    /// directly), so this exports to a temp file first and atomically
    /// replaces `finalURL` with it, then removes the other segment files.
    /// Re-encodes (AVAssetExportPresetHighestQuality) rather than
    /// attempting a passthrough export: every segment is produced by the
    /// same recording config, so passthrough would likely work, but
    /// correctness here matters far more than the few extra seconds a
    /// re-encode costs for what should be an occasional operation.
    private static func concatenateSegments(_ urls: [URL], into finalURL: URL, fileType: AVFileType) async throws {
        let composition = AVMutableComposition()
        var compositionVideoTrack: AVMutableCompositionTrack?
        var compositionAudioTracks: [AVMutableCompositionTrack] = []
        var cursor = CMTime.zero

        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)

            if let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first {
                if compositionVideoTrack == nil {
                    compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                    if let transform = try? await sourceVideoTrack.load(.preferredTransform) {
                        compositionVideoTrack?.preferredTransform = transform
                    }
                }
                try? compositionVideoTrack?.insertTimeRange(range, of: sourceVideoTrack, at: cursor)
            }

            // Paired by index, not by any track identity ScreenCaptureKit
            // exposes (there isn't one) — safe because every segment comes
            // from the exact same recording config, so track order/count is
            // consistent across segments in practice. A segment with fewer
            // audio tracks than an earlier one just leaves that range
            // silent on the extra track(s), not a crash.
            let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
            for (index, sourceAudioTrack) in sourceAudioTracks.enumerated() {
                while compositionAudioTracks.count <= index {
                    guard let newTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { break }
                    compositionAudioTracks.append(newTrack)
                }
                guard index < compositionAudioTracks.count else { continue }
                try? compositionAudioTracks[index].insertTimeRange(range, of: sourceAudioTrack, at: cursor)
            }

            cursor = cursor + duration
        }

        let tempURL = finalURL.deletingLastPathComponent()
            .appendingPathComponent(".recorgi-merge-\(UUID().uuidString)")
            .appendingPathExtension(finalURL.pathExtension)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw RecordingError.recordingSetupFailed("Could not prepare to merge paused segments.")
        }
        try await exportSession.export(to: tempURL, as: fileType)

        _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: tempURL)
        for url in urls where url.path != finalURL.path {
            try? FileManager.default.removeItem(at: url)
        }
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
                    Log.capture.error("legacy videoInput.append() returned FALSE at frame \(self.videoFrameCount, privacy: .public), writer.status=\(self.assetWriter?.status.rawValue ?? -1, privacy: .public) error=\(self.assetWriter?.error?.localizedDescription ?? "nil", privacy: .public)")
                }
            } else {
                droppedNotReadyCount += 1
            }
        case .systemAudio:
            if let last = lastSystemAudioPTS, pts <= last { return }
            // Live volume/mute for the one app this pipeline is scoped to
            // — see AudioSampleBufferGain's own doc comment for why this
            // is only reachable (and only correct) for that case, never
            // for "entire system".
            let gain: Float = activeSettings?.isSystemAudioMuted == true ? 0 : Float(activeSettings?.systemAudioVolume ?? 1.0)
            AudioSampleBufferGain.apply(gain, to: sampleBuffer)
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
        Log.capture.error("handleWriterFailure() triggered from append(): \(message, privacy: .public)")
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
            Log.capture.error("SCStream didStopWithError: \(error.localizedDescription, privacy: .public)")
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
        Log.capture.notice("SCRecordingOutput: recording started")
    }

    nonisolated public func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Log.capture.error("SCRecordingOutput: didFailWithError \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in
            self.lastError = error.localizedDescription
            self.recordingStopContinuation?.resume()
            self.recordingStopContinuation = nil
        }
    }

    nonisolated public func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Log.capture.notice("SCRecordingOutput: finished recording ok")
        Task { @MainActor in
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
