import SwiftUI

/// SwiftUI's own `accessibilityReduceTransparency` environment value is
/// get-only in this SDK — apps can read the live system setting, but can't
/// override it via `.environment(_:_:)` the way `.tint()` or other
/// environment values can be. So instead of faking that key, this is a
/// separate key GlassCard reads directly: nil leaves GlassCard following
/// the real system value (which updates live if the user changes it while
/// the app is running); a non-nil value overrides it for this app only.
///
/// This only affects views that explicitly read it, like GlassCard — it
/// has no way to reach the native `.glass`/`.glassProminent` button bezels
/// scattered through the app, since those are rendered by the system and
/// only ever follow the real, systemwide Reduce Transparency setting.
private struct ReduceTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var reduceTransparencyOverride: Bool? {
        get { self[ReduceTransparencyOverrideKey.self] }
        set { self[ReduceTransparencyOverrideKey.self] = newValue }
    }
}
