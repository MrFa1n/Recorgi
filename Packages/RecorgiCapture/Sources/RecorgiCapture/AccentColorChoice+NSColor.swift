import AppKit
import RecorgiCore

public extension AccentColorChoice {
    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}
