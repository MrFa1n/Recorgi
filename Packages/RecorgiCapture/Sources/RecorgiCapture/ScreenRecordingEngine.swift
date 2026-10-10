import Foundation
import AppKit
import AVFoundation
import ScreenCaptureKit
import Combine
import RecorgiCore

public enum RecordingError: LocalizedError {
    case noDisplayAvailable
    case noMicrophoneAvailable
    case microphoneSetupFailed
    case audioApplicationUnavailable

    public var errorDescription: String? {
        switch self {
        case .noDisplayAvailable: return "No display available to record."
        case .noMicrophoneAvailable: return "No microphone available."
        case .microphoneSetupFailed: return "Could not set up the microphone input."
        case .audioApplicationUnavailable: return "The selected app is no longer available to capture audio from."
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

    private var sessionStarted = false

    public override init() {
        super.init()
    }

    public func start(settings: RecordingSettings) async throws {
        guard case .idle = state else { return }
        lastError = nil

        try FileManager.default.createDirectory(at: settings.saveDirectory, withIntermediateDirectories: true)
        let fileURL = settings.saveDirectory.appendingPathComponent(Self.timestampedFilename())
        let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw RecordingError.noDisplayAvailable
        }

        let isAppScoped: Bool
        if case .application = settings.systemAudioScope {
            isAppScoped = true
        } else {
            isAppScoped = false
        }
        let capturesWholeSystemAudio = settings.isSystemAudioEnabled && !isAppScoped

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = Self.backingScaleFactor(for: display.displayID)
        let pixelWidth = Int(Double(display.width) * scale)
        let pixelHeight = Int(Double(display.height) * scale)

        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = true
        config.capturesAudio = capturesWholeSystemAudio
        config.sampleRate = 48_000
        config.channelCount = 2

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight
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
        self.sessionStarted = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        if capturesWholeSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
        }
        try await stream.startCapture()
        self.stream = stream

        if settings.isSystemAudioEnabled, case .application(let app) = settings.systemAudioScope {
            guard let match = content.applications.first(where: { $0.processID == app.processID }) else {
                throw RecordingError.audioApplicationUnavailable
            }
            let appFilter = SCContentFilter(display: display, including: [match], exceptingWindows: [])
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
        state = .recording(startedAt: Date())
    }

    public func stop() async {
        guard case .recording = state else { return }
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

        if let writer = assetWriter, writer.status == .writing {
            await writer.finishWriting()
        }
        assetWriter = nil
        videoInput = nil
        systemAudioInput = nil
        microphoneInput = nil

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

    private func append(_ sampleBuffer: CMSampleBuffer, to track: TrackKind) {
        guard let writer = assetWriter, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        if !sessionStarted {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            sessionStarted = true
        }

        switch track {
        case .video:
            if videoInput?.isReadyForMoreMediaData == true {
                videoInput?.append(sampleBuffer)
            }
        case .systemAudio:
            if systemAudioInput?.isReadyForMoreMediaData == true {
                systemAudioInput?.append(sampleBuffer)
            }
        case .microphone:
            if microphoneInput?.isReadyForMoreMediaData == true {
                microphoneInput?.append(sampleBuffer)
            }
        }
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
