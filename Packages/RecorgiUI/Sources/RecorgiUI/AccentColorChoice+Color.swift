import SwiftUI
import AppKit
import RecorgiCore

extension AccentColorChoice {
    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    init(color: Color) {
        // Resolved via NSColor for reliable component extraction regardless
        // of which color space `color` was created in (presets, the system
        // color panel, etc. can differ).
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        self.init(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent)
    }
}
