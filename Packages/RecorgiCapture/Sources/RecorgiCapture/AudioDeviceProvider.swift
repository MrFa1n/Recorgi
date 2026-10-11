import AVFoundation
import RecorgiCore

public struct AudioDeviceProvider: Sendable {
    public init() {}

    public func availableMicrophones() -> [AudioInputDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discovery.devices.map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
        Log.devices.debug("availableMicrophones(): found \(devices.count, privacy: .public)")
        return devices
    }

    public func availableOutputDevices() -> [AudioOutputDevice] {
        let devices = CoreAudioOutputDeviceLister.listOutputDevices()
        Log.devices.debug("availableOutputDevices(): found \(devices.count, privacy: .public)")
        return devices
    }
}
