import CoreAudio
import Foundation
import RecorgiCore

/// Lists CoreAudio devices that have output streams (speakers, headphones,
/// etc), for picking where to send live microphone monitoring. AVFoundation
/// has no high-level API for this — only CoreAudio's device-object property
/// system reaches playback devices.
struct CoreAudioOutputDeviceLister {
    static func listOutputDevices() -> [AudioOutputDevice] {
        guard let deviceIDs = allDeviceIDs() else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard hasOutputStreams(deviceID), let uid = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) else {
                return nil
            }
            let name = stringProperty(deviceID, selector: kAudioObjectPropertyName) ?? uid
            return AudioOutputDevice(id: uid, name: name)
        }
    }

    private static func allDeviceIDs() -> [AudioDeviceID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: AudioDeviceID(), count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return nil }
        return deviceIDs
    }

    private static func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private static func stringProperty(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer -> OSStatus in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr else { return nil }
        return value as String
    }
}
