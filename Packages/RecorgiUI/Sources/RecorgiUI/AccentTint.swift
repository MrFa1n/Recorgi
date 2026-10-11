import SwiftUI

/// Carries the user's accent-color choice (nil = follow the system) down
/// through the view tree WITHOUT touching SwiftUI's own `.tint()`
/// environment value. Keeping it a separate key means only controls that
/// explicitly opt in via `.themedTint()` react to the choice — everything
/// else (plain `.glass` buttons, links, icons that never were tinted blue)
/// is left exactly as macOS renders it by default, same as before this
/// setting existed. A blanket `.tint(accentColor)` at the app root was
/// tried first and rejected: Liquid Glass's `.glass` button style turns out
/// to pick up ambient `.tint()` too, not just `.glassProminent`, so it
/// recolored buttons that had never been blue in the first place.
private struct AccentTintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var accentTint: Color? {
        get { self[AccentTintKey.self] }
        set { self[AccentTintKey.self] = newValue }
    }
}

extension View {
    /// Applies the user's accent-color choice as this view's `.tint()`.
    /// Use only on controls that are already blue by default
    /// (`.glassProminent` buttons, `.foregroundStyle(.tint)` text) — never
    /// globally.
    func themedTint() -> some View {
        modifier(ThemedTintModifier())
    }
}

private struct ThemedTintModifier: ViewModifier {
    @Environment(\.accentTint) private var accentTint
    func body(content: Content) -> some View {
        content.tint(accentTint)
    }
}
