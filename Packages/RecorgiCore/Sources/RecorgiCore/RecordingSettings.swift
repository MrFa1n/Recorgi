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

    /// nil means "follow the system" (System Settings > Accessibility >
    /// Display > Reduce Transparency) — the original, still-default
    /// behavior; SwiftUI's glass effects already respect that setting on
    /// their own.
    @Published public var transparencyMode: TransparencyMode? {
        didSet { Self.persist(transparencyMode) }
    }

    private static let accentColorDefaultsKey = "recorgi.accentColor"
    private static let appearanceModeDefaultsKey = "recorgi.appearanceMode"
    private static let transparencyModeDefaultsKey = "recorgi.transparencyMode"

    public init() {
        let moviesDirectory = FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        self.saveDirectory = moviesDirectory.appendingPathComponent("Recorgi", isDirectory: true)
        self.accentColor = Self.loadPersistedAccentColor()
        self.appearanceMode = Self.loadPersistedAppearanceMode()
        self.transparencyMode = Self.loadPersistedTransparencyMode()
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

    private static func loadPersistedTransparencyMode() -> TransparencyMode? {
        guard let raw = UserDefaults.standard.string(forKey: transparencyModeDefaultsKey) else { return nil }
        return TransparencyMode(rawValue: raw)
    }

    private static func persist(_ mode: TransparencyMode?) {
        guard let mode else {
            UserDefaults.standard.removeObject(forKey: transparencyModeDefaultsKey)
            return
        }
        UserDefaults.standard.set(mode.rawValue, forKey: transparencyModeDefaultsKey)
    }
}
