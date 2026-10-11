import Foundation

/// A plain RGB triple, deliberately not AppKit's NSColor or SwiftUI's
/// Color — RecorgiCore stays free of UI-framework imports, same as every
/// other model here. RecorgiCapture and RecorgiUI each add their own small
/// conversion to the type they need (NSColor / Color respectively).
public struct AccentColorChoice: Equatable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// The solid preset swatches macOS's own Appearance settings offer
/// (everything but "Multicolor," which isn't expressible as one flat tint).
public enum AccentColorPreset: String, CaseIterable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, graphite

    public var choice: AccentColorChoice {
        switch self {
        case .blue: return AccentColorChoice(red: 0.0, green: 0.478, blue: 1.0)
        case .purple: return AccentColorChoice(red: 0.686, green: 0.321, blue: 0.871)
        case .pink: return AccentColorChoice(red: 1.0, green: 0.176, blue: 0.333)
        case .red: return AccentColorChoice(red: 1.0, green: 0.231, blue: 0.188)
        case .orange: return AccentColorChoice(red: 1.0, green: 0.584, blue: 0.0)
        case .yellow: return AccentColorChoice(red: 1.0, green: 0.800, blue: 0.0)
        case .green: return AccentColorChoice(red: 0.204, green: 0.780, blue: 0.349)
        case .graphite: return AccentColorChoice(red: 0.557, green: 0.557, blue: 0.576)
        }
    }

    public var label: String {
        switch self {
        case .blue: return "Синий"
        case .purple: return "Фиолетовый"
        case .pink: return "Розовый"
        case .red: return "Красный"
        case .orange: return "Оранжевый"
        case .yellow: return "Жёлтый"
        case .green: return "Зелёный"
        case .graphite: return "Графитовый"
        }
    }
}
