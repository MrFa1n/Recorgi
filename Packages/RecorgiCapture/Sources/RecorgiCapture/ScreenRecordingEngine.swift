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

    public var errorDescription: String? {
        switch self {
        case .noDisplayAvailable: return "No display available to record."
        case .noMicrophoneAvailable: return "No microphone available."
        case .microphoneSetupFailed: return "Could not set up the microphone input."
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

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = Self.backingScaleFactor(for: display.displayID)
        let pixelWidth = Int(Double(display.width) * scale)
        let pixelHeight = Int(Double(display.height) * scale)

        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = true
        config.capturesAudio = settings.isSystemAudioEnabled
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
            try setUpMicrophoneCapture(deviceID: settings.selectedMicrophoneID)
        }

        self.assetWriter = writer
        self.sessionStarted = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        if settings.isSystemAudioEnabled {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
        }
        try await stream.startCapture()
        self.stream = stream

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

    private func setUpMicrophoneCapture(deviceID: String?) throws {
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
            Task { @MainActor [weak self] in
                self?.append(sampleBuffer, to: .microphone)
            }
        }
        output.setSampleBufferDelegate(relay, queue: microphoneQueue)
        guard session.canAddOutput(output) else { throw RecordingError.microphoneSetupFailed }
        session.addOutput(output)

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
    // Both requirements are nonisolated protocol methods; SCStream already
    // delivers them on the main queue (sampleHandlerQueue: .main), so hopping
    // to the main actor here is just making that explicit to the compiler.
    nonisolated public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        Task { @MainActor in
            switch type {
            case .screen:
                self.append(sampleBuffer, to: .video)
            case .audio:
                self.append(sampleBuffer, to: .systemAudio)
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
        Task { @MainActor in
            self.lastError = error.localizedDescription
            await self.stop()
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
