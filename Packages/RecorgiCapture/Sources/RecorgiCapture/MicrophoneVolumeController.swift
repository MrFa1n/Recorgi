import CoreAudio
import Foundation
import RecorgiCore

/// Reads and sets the selected microphone's hardware input gain via
/// CoreAudio — AVFoundation has no API for this, only the device-object
/// property system does. This is the exact same scalar System Settings >
/// Sound > Input's own volume slider controls, so it's a real, live,
/// system-level setting: a change takes effect immediately whether or not a
/// recording is in progress, and persists as that device's own gain until
/// changed again (by this app or anything else) — there is no separate
/// "recording-only" gain to apply after the fact.
public struct MicrophoneVolumeController {
    /// `deviceUID` nil means "the system default input device" — mirrors
    /// RecordingSettings.selectedMicrophoneID's own "По умолчанию" meaning.
    /// Returns nil if the device can't be found or exposes no readable
    /// volume control at all.
    public static func currentVolume(deviceUID: String?) -> Float? {
        guard let deviceID = resolveDeviceID(uid: deviceUID) else { return nil }
        return getScalar(deviceID: deviceID, element: kAudioObjectPropertyElementMain)
            ?? getScalar(deviceID: deviceID, element: 1)
    }

    /// `volume` is 0...1, matching CoreAudio's own scalar range; out-of-range
    /// values are clamped. Silently does nothing (besides logging) if the
    /// device can't be found or has no settable volume control — some
    /// devices (certain webcams, aggregate devices) genuinely don't expose
    /// one, same as they'd show no usable slider in System Settings either.
    public static func setVolume(_ volume: Float, deviceUID: String?) {
        guard let deviceID = resolveDeviceID(uid: deviceUID) else {
            Log.devices.error("MicrophoneVolumeController.setVolume: no input device found for uid=\(deviceUID ?? "<default>", privacy: .public)")
            return
        }

        let clamped = min(max(volume, 0), 1)

        if setScalar(clamped, deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return
        }
        // Some microphones expose only per-channel volume, not a single
        // master control — fall back to setting every input channel
        // individually rather than giving up.
        let didSetChannel1 = setScalar(clamped, deviceID: deviceID, element: 1)
        let didSetChannel2 = setScalar(clamped, deviceID: deviceID, element: 2)
        if !didSetChannel1 && !didSetChannel2 {
            Log.devices.error("MicrophoneVolumeController.setVolume: device has no settable volume control, deviceID=\(deviceID, privacy: .public)")
        }
    }

    private static func getScalar(deviceID: AudioDeviceID, element: UInt32) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var value: Float = 0
        var dataSize = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        return status == noErr ? value : nil
    }

    private static func setScalar(_ volume: Float, deviceID: AudioDeviceID, element: UInt32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr, isSettable.boolValue else { return false }

        var value = volume
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &value)
        return status == noErr
    }

    /// Not private: MicrophoneLivePreviewEngine also needs to turn a
    /// device UID (or nil for "system default") into a concrete
    /// AudioDeviceID, to point AVAudioEngine's input/output units at the
    /// same devices the rest of the app's device pickers refer to.
    /// `isInput` only matters when `uid` is nil — it picks which "system
    /// default" device nil should resolve to.
    static func resolveDeviceID(uid: String?, isInput: Bool = true) -> AudioDeviceID? {
        guard let uid else { return isInput ? defaultInputDeviceID() : defaultOutputDeviceID() }
        return allDeviceIDs()?.first { stringProperty($0, selector: kAudioDevicePropertyDeviceUID) == uid }
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    private static func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
        return status == noErr ? deviceID : nil
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
        return status == noErr ? deviceIDs : nil
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
        return status == noErr ? (value as String) : nil
    }
}
