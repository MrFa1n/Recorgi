/// How translucent GlassCard panels render. nil (on
/// `RecordingSettings.transparencyMode`) means "follow the system" —
/// System Settings > Accessibility > Display > Reduce Transparency, the
/// original, still-default behavior — which only ever reports on or off,
/// so "system" resolves to `.regular` or `.minimal`. A non-nil choice
/// overrides it for this app and can pick `.medium` too, a middle degree
/// the system accessibility setting itself has no equivalent for.
public enum TransparencyMode: String, CaseIterable, Sendable {
    case regular, medium, minimal

    public var label: String {
        switch self {
        case .regular: return "Обычная"
        case .medium: return "Средняя"
        case .minimal: return "Минимальная"
        }
    }

    public var systemImage: String {
        switch self {
        case .regular: return "square.stack.3d.up.fill"
        case .medium: return "square.stack.3d.up"
        case .minimal: return "square.fill"
        }
    }
}
