import Foundation

/// A playback device, used for picking where live microphone monitoring is
/// heard. Monitoring never changes what's recorded, only what the user hears
/// back while recording.
public struct AudioOutputDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
