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
    /// 0...1, matching CoreAudio's own input-gain scalar. nil means "never
    /// touched" — leave the microphone's hardware volume exactly as the
    /// system (or the user, outside this app) already has it, rather than
    /// silently forcing it to some default the first time this app runs.
    /// Only gets a concrete value once the user actually drags the slider
    /// in Audio Sources — see AudioSourcesView and MicrophoneVolumeController
    /// (RecorgiCapture), which is what actually applies it via CoreAudio;
    /// this type stays free of that import on purpose (see architecture
    /// note in CLAUDE.md).
    @Published public var microphoneVolume: Double? {
        didSet { Self.persist(microphoneVolume, key: Self.microphoneVolumeDefaultsKey) }
    }
    @Published public var isMonitoringEnabled: Bool = false
    @Published public var selectedMonitoringOutputID: String?
    /// Chosen in Audio Sources settings (live-previewable there via
    /// MicrophoneLivePreviewEngine) and reused as the recording editor's
    /// starting value for the same recording's microphone track, so
    /// there's no need to re-pick the level that was just auditioned.
    @Published public var microphoneNoiseSuppression: NoiseSuppressionLevel = .off {
        didSet { Self.persist(microphoneNoiseSuppression) }
    }
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

    /// nil means unset — no global hotkey registered for that action.
    /// Starts out at the matching `default…Hotkey` below on a fresh
    /// install; the user can clear or reassign any of them individually in
    /// General settings, and a "Сбросить по умолчанию" button there calls
    /// `resetHotkeysToDefaults()`. GlobalHotkeyManager (RecorgiCapture) is
    /// what actually registers these with the system.
    @Published public var startStopHotkey: HotkeyBinding? {
        didSet { Self.persist(startStopHotkey, key: Self.startStopHotkeyDefaultsKey) }
    }

    @Published public var toggleMicrophoneHotkey: HotkeyBinding? {
        didSet { Self.persist(toggleMicrophoneHotkey, key: Self.toggleMicrophoneHotkeyDefaultsKey) }
    }

    @Published public var toggleSystemAudioHotkey: HotkeyBinding? {
        didSet { Self.persist(toggleSystemAudioHotkey, key: Self.toggleSystemAudioHotkeyDefaultsKey) }
    }

    @Published public var pauseResumeHotkey: HotkeyBinding? {
        didSet { Self.persist(pauseResumeHotkey, key: Self.pauseResumeHotkeyDefaultsKey) }
    }

    public static let defaultStartStopHotkey = HotkeyBinding(keyCode: 25, modifiers: [.command, .shift], displayLabel: "⌘⇧9")
    public static let defaultToggleMicrophoneHotkey = HotkeyBinding(keyCode: 46, modifiers: [.command, .shift], displayLabel: "⌘⇧M")
    public static let defaultToggleSystemAudioHotkey = HotkeyBinding(keyCode: 1, modifiers: [.command, .shift], displayLabel: "⌘⇧S")
    public static let defaultPauseResumeHotkey = HotkeyBinding(keyCode: 35, modifiers: [.command, .shift], displayLabel: "⌘⇧P")

    public func resetHotkeysToDefaults() {
        startStopHotkey = Self.defaultStartStopHotkey
        toggleMicrophoneHotkey = Self.defaultToggleMicrophoneHotkey
        toggleSystemAudioHotkey = Self.defaultToggleSystemAudioHotkey
        pauseResumeHotkey = Self.defaultPauseResumeHotkey
    }

    private static let accentColorDefaultsKey = "recorgi.accentColor"
    private static let appearanceModeDefaultsKey = "recorgi.appearanceMode"
    private static let videoCodecDefaultsKey = "recorgi.videoCodec"
    private static let videoContainerDefaultsKey = "recorgi.videoContainer"
    private static let recordingQualityDefaultsKey = "recorgi.recordingQuality"
    private static let startStopHotkeyDefaultsKey = "recorgi.startStopHotkey"
    private static let toggleMicrophoneHotkeyDefaultsKey = "recorgi.toggleMicrophoneHotkey"
    private static let toggleSystemAudioHotkeyDefaultsKey = "recorgi.toggleSystemAudioHotkey"
    private static let pauseResumeHotkeyDefaultsKey = "recorgi.pauseResumeHotkey"
    private static let microphoneVolumeDefaultsKey = "recorgi.microphoneVolume"
    private static let microphoneNoiseSuppressionDefaultsKey = "recorgi.microphoneNoiseSuppression"

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
        self.startStopHotkey = Self.loadPersistedHotkey(key: Self.startStopHotkeyDefaultsKey, default: Self.defaultStartStopHotkey)
        self.toggleMicrophoneHotkey = Self.loadPersistedHotkey(key: Self.toggleMicrophoneHotkeyDefaultsKey, default: Self.defaultToggleMicrophoneHotkey)
        self.toggleSystemAudioHotkey = Self.loadPersistedHotkey(key: Self.toggleSystemAudioHotkeyDefaultsKey, default: Self.defaultToggleSystemAudioHotkey)
        self.pauseResumeHotkey = Self.loadPersistedHotkey(key: Self.pauseResumeHotkeyDefaultsKey, default: Self.defaultPauseResumeHotkey)
        self.microphoneVolume = Self.loadPersistedMicrophoneVolume()
        self.microphoneNoiseSuppression = Self.loadPersistedMicrophoneNoiseSuppression()
    }

    private static func loadPersistedMicrophoneNoiseSuppression() -> NoiseSuppressionLevel {
        UserDefaults.standard.string(forKey: microphoneNoiseSuppressionDefaultsKey).flatMap(NoiseSuppressionLevel.init(rawValue:)) ?? .off
    }

    private static func persist(_ level: NoiseSuppressionLevel) {
        UserDefaults.standard.set(level.rawValue, forKey: microphoneNoiseSuppressionDefaultsKey)
    }

    private static func loadPersistedMicrophoneVolume() -> Double? {
        guard UserDefaults.standard.object(forKey: microphoneVolumeDefaultsKey) != nil else { return nil }
        return UserDefaults.standard.double(forKey: microphoneVolumeDefaultsKey)
    }

    private static func persist(_ volume: Double?, key: String) {
        guard let volume else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(volume, forKey: key)
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

    // No UserDefaults entry at all means "never touched" -> use the
    // default. An explicit clear (binding set to nil) still has to leave
    // *some* trace, or it would be indistinguishable from "never touched"
    // on next launch and the default would silently come back — so
    // clearing writes an empty Data() sentinel instead of removing the
    // key.
    private static func loadPersistedHotkey(key: String, default defaultValue: HotkeyBinding) -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return defaultValue }
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }

    private static func persist(_ binding: HotkeyBinding?, key: String) {
        guard let binding, let data = try? JSONEncoder().encode(binding) else {
            UserDefaults.standard.set(Data(), forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}
