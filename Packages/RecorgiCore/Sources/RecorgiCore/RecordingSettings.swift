import Foundation
import Combine

/// User-configurable recording preferences, plus app-wide appearance
/// (accent color) — kept on the same object rather than a separate one
/// purely to avoid threading a second settings object through every view
/// and through ScreenRecordingEngine.start(), which already takes this one.
/// Both audio sources default to on, matching the "just works" capture
/// flow of Windows' built-in recorders — the user opts out rather than
/// having to discover and opt in.
public final class RecordingSettings: ObservableObject {
    @Published public var captureRegion: CaptureRegion = .primaryDisplay
    @Published public var isSystemAudioEnabled: Bool = true
    @Published public var systemAudioScope: SystemAudioScope = .entireSystem
    @Published public var isMicrophoneEnabled: Bool = true
    @Published public var selectedMicrophoneID: String?
    @Published public var isMonitoringEnabled: Bool = false
    @Published public var selectedMonitoringOutputID: String?
    @Published public var saveDirectory: URL

    /// nil means "follow the system accent color" (System Settings >
    /// Appearance) — the original, still-default behavior. A non-nil value
    /// overrides it everywhere: SwiftUI's .tint() and the capture-area
    /// highlight border/handles AppKit draws directly.
    @Published public var accentColor: AccentColorChoice? {
        didSet { Self.persist(accentColor) }
    }

    /// nil means "follow the system" (light/dark switches with System
    /// Settings > Appearance) — the original, still-default behavior.
    @Published public var appearanceMode: AppearanceMode? {
        didSet { Self.persist(appearanceMode) }
    }

    /// No "system" option for either of these — there's nothing in System
    /// Settings for a screen recorder's own output codec/container to
    /// follow. H.264 + .mov match what this always recorded with.
    @Published public var videoCodec: VideoCodec = .h264 {
        didSet { Self.persist(videoCodec) }
    }

    @Published public var videoContainer: VideoContainer = .mov {
        didSet { Self.persist(videoContainer) }
    }

    /// See RecordingQuality's own doc comment for why this is
    /// resolution/frame-rate presets rather than a bitrate slider.
    @Published public var recordingQuality: RecordingQuality = .high {
        didSet { Self.persist(recordingQuality) }
    }

    /// nil means unset — no global hotkey registered for that action. No
    /// default binding is pre-assigned, since guessing a key combo could
    /// collide with something the user already relies on elsewhere; they
    /// opt in explicitly in General settings. GlobalHotkeyManager
    /// (RecorgiCapture) is what actually registers these with the system.
    @Published public var startStopHotkey: HotkeyBinding? {
        didSet { Self.persist(startStopHotkey, key: Self.startStopHotkeyDefaultsKey) }
    }

    @Published public var toggleMicrophoneHotkey: HotkeyBinding? {
        didSet { Self.persist(toggleMicrophoneHotkey, key: Self.toggleMicrophoneHotkeyDefaultsKey) }
    }

    @Published public var toggleSystemAudioHotkey: HotkeyBinding? {
        didSet { Self.persist(toggleSystemAudioHotkey, key: Self.toggleSystemAudioHotkeyDefaultsKey) }
    }

    private static let accentColorDefaultsKey = "recorgi.accentColor"
    private static let appearanceModeDefaultsKey = "recorgi.appearanceMode"
    private static let videoCodecDefaultsKey = "recorgi.videoCodec"
    private static let videoContainerDefaultsKey = "recorgi.videoContainer"
    private static let recordingQualityDefaultsKey = "recorgi.recordingQuality"
    private static let startStopHotkeyDefaultsKey = "recorgi.startStopHotkey"
    private static let toggleMicrophoneHotkeyDefaultsKey = "recorgi.toggleMicrophoneHotkey"
    private static let toggleSystemAudioHotkeyDefaultsKey = "recorgi.toggleSystemAudioHotkey"

    public init() {
        let moviesDirectory = FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        self.saveDirectory = moviesDirectory.appendingPathComponent("Recorgi", isDirectory: true)
        self.accentColor = Self.loadPersistedAccentColor()
        self.appearanceMode = Self.loadPersistedAppearanceMode()
        self.videoCodec = Self.loadPersistedVideoCodec()
        self.videoContainer = Self.loadPersistedVideoContainer()
        self.recordingQuality = Self.loadPersistedRecordingQuality()
        self.startStopHotkey = Self.loadPersistedHotkey(key: Self.startStopHotkeyDefaultsKey)
        self.toggleMicrophoneHotkey = Self.loadPersistedHotkey(key: Self.toggleMicrophoneHotkeyDefaultsKey)
        self.toggleSystemAudioHotkey = Self.loadPersistedHotkey(key: Self.toggleSystemAudioHotkeyDefaultsKey)
    }

    private static func loadPersistedAccentColor() -> AccentColorChoice? {
        guard let data = UserDefaults.standard.data(forKey: accentColorDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(AccentColorChoice.self, from: data)
    }

    private static func persist(_ choice: AccentColorChoice?) {
        guard let choice, let data = try? JSONEncoder().encode(choice) else {
            UserDefaults.standard.removeObject(forKey: accentColorDefaultsKey)
            return
        }
        UserDefaults.standard.set(data, forKey: accentColorDefaultsKey)
    }

    private static func loadPersistedAppearanceMode() -> AppearanceMode? {
        guard let raw = UserDefaults.standard.string(forKey: appearanceModeDefaultsKey) else { return nil }
        return AppearanceMode(rawValue: raw)
    }

    private static func persist(_ mode: AppearanceMode?) {
        guard let mode else {
            UserDefaults.standard.removeObject(forKey: appearanceModeDefaultsKey)
            return
        }
        UserDefaults.standard.set(mode.rawValue, forKey: appearanceModeDefaultsKey)
    }

    private static func loadPersistedVideoCodec() -> VideoCodec {
        UserDefaults.standard.string(forKey: videoCodecDefaultsKey).flatMap(VideoCodec.init(rawValue:)) ?? .h264
    }

    private static func persist(_ codec: VideoCodec) {
        UserDefaults.standard.set(codec.rawValue, forKey: videoCodecDefaultsKey)
    }

    private static func loadPersistedVideoContainer() -> VideoContainer {
        UserDefaults.standard.string(forKey: videoContainerDefaultsKey).flatMap(VideoContainer.init(rawValue:)) ?? .mov
    }

    private static func persist(_ container: VideoContainer) {
        UserDefaults.standard.set(container.rawValue, forKey: videoContainerDefaultsKey)
    }

    private static func loadPersistedRecordingQuality() -> RecordingQuality {
        UserDefaults.standard.string(forKey: recordingQualityDefaultsKey).flatMap(RecordingQuality.init(rawValue:)) ?? .high
    }

    private static func persist(_ quality: RecordingQuality) {
        UserDefaults.standard.set(quality.rawValue, forKey: recordingQualityDefaultsKey)
    }

    private static func loadPersistedHotkey(key: String) -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }

    private static func persist(_ binding: HotkeyBinding?, key: String) {
        guard let binding, let data = try? JSONEncoder().encode(binding) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}
