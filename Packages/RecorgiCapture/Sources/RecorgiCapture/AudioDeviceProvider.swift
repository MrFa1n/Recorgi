import AVFoundation
import RecorgiCore

public struct AudioDeviceProvider {
    public init() {}

    public func availableMicrophones() -> [AudioInputDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    public func availableOutputDevices() -> [AudioOutputDevice] {
        CoreAudioOutputDeviceLister.listOutputDevices()
    }
}
