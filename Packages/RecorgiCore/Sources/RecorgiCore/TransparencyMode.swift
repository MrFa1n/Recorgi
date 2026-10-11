/// How translucent the app's Liquid Glass surfaces (GlassCard, glass button
/// styles, the capture-area border) render. nil (on
/// `RecordingSettings.transparencyMode`) means "follow the system" —
/// System Settings > Accessibility > Display > Reduce Transparency, the
/// original, still-default behavior. SwiftUI's glass effects already
/// respect that accessibility setting on their own; this just lets the
/// user override it for this app specifically, same as appearance and
/// accent color.
public enum TransparencyMode: String, CaseIterable, Sendable {
    case normal, reduced

    public var label: String {
        switch self {
        case .normal: return "Обычная"
        case .reduced: return "Уменьшенная"
        }
    }

    public var systemImage: String {
        switch self {
        case .normal: return "square.stack.3d.up.fill"
        case .reduced: return "square.fill"
        }
    }
}
