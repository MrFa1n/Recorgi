import Foundation

public struct WindowInfo: Identifiable, Hashable, Sendable {
    public let windowID: UInt32
    public let title: String
    public let appName: String
    public let processID: Int32
    public let width: Int
    public let height: Int

    public var id: UInt32 { windowID }

    public init(windowID: UInt32, title: String, appName: String, processID: Int32, width: Int, height: Int) {
        self.windowID = windowID
        self.title = title
        self.appName = appName
        self.processID = processID
        self.width = width
        self.height = height
    }
}
