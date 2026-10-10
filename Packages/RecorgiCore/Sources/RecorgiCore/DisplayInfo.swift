import Foundation

public struct DisplayInfo: Identifiable, Hashable, Sendable {
    public let displayID: UInt32
    public let name: String
    public let width: Int
    public let height: Int

    public var id: UInt32 { displayID }

    public init(displayID: UInt32, name: String, width: Int, height: Int) {
        self.displayID = displayID
        self.name = name
        self.width = width
        self.height = height
    }
}
