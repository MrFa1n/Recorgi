import Foundation
import Combine

/// User-configurable recording preferences. Both audio sources default to on,
/// matching the "just works" capture flow of Windows' built-in recorders —
/// the user opts out rather than having to discover and opt in.
public final class RecordingSettings: ObservableObject {
    @Published public var isSystemAudioEnabled: Bool = true
    @Published public var systemAudioScope: SystemAudioScope = .entireSystem
    @Published public var isMicrophoneEnabled: Bool = true
    @Published public var selectedMicrophoneID: String?
    @Published public var isMonitoringEnabled: Bool = false
    @Published public var selectedMonitoringOutputID: String?
    @Published public var saveDirectory: URL

    public init() {
        let moviesDirectory = FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        self.saveDirectory = moviesDirectory.appendingPathComponent("Recorgi", isDirectory: true)
    }
}
