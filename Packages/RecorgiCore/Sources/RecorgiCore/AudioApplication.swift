import Foundation

/// A running application that can be used to scope system-audio capture to
/// just that app (OBS calls this "Application Audio Capture"), instead of
/// the whole system mix.
public struct AudioApplication: Identifiable, Hashable, Sendable {
    public let processID: Int32
    public let bundleIdentifier: String
    public let name: String

    public var id: Int32 { processID }

    public init(processID: Int32, bundleIdentifier: String, name: String) {
        self.processID = processID
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}
