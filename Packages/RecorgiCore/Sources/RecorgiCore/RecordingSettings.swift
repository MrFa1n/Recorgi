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

    private static let accentColorDefaultsKey = "recorgi.accentColor"

    public init() {
        let moviesDirectory = FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        self.saveDirectory = moviesDirectory.appendingPathComponent("Recorgi", isDirectory: true)
        self.accentColor = Self.loadPersistedAccentColor()
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
}
