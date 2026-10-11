/// Which light/dark appearance the app's own windows use. nil (on
/// `RecordingSettings.appearanceMode`) means "follow the system" — the
/// original, still-default behavior.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case light, dark

    public var label: String {
        switch self {
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    public var systemImage: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}
