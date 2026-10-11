import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreGraphics
import Combine
import RecorgiCore

/// Requests screen-recording and microphone access up front, at launch,
/// rather than waiting for the user to hit Record and discover a permission
/// prompt mid-flow.
@MainActor
public final class PermissionsManager: ObservableObject {
    @Published public private(set) var microphoneStatus: PermissionStatus = .notDetermined
    @Published public private(set) var screenRecordingStatus: PermissionStatus = .notDetermined

    public init() {
        refresh()
    }

    public func refresh() {
        microphoneStatus = Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        screenRecordingStatus = CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        Log.permissions.notice("refresh(): mic=\(String(describing: self.microphoneStatus), privacy: .public) screenRecording=\(String(describing: self.screenRecordingStatus), privacy: .public)")
    }

    public func requestAll() async {
        async let mic: PermissionStatus = requestMicrophone()
        async let screen: PermissionStatus = requestScreenRecording()
        _ = await (mic, screen)
    }

    @discardableResult
    public func requestMicrophone() async -> PermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        let status: PermissionStatus = granted ? .granted : .denied
        microphoneStatus = status
        Log.permissions.notice("requestMicrophone() -> \(String(describing: status), privacy: .public)")
        return status
    }

    @discardableResult
    public func requestScreenRecording() async -> PermissionStatus {
        // ScreenCaptureKit has no explicit "request access" call: fetching
        // shareable content is itself what triggers the system TCC prompt
        // the first time it's called.
        let status: PermissionStatus
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            status = .granted
        } catch {
            Log.permissions.notice("requestScreenRecording(): SCShareableContent fetch threw \(error.localizedDescription, privacy: .public), falling back to CGPreflightScreenCaptureAccess")
            status = CGPreflightScreenCaptureAccess() ? .granted : .denied
        }
        screenRecordingStatus = status
        Log.permissions.notice("requestScreenRecording() -> \(String(describing: status), privacy: .public)")
        return status
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
