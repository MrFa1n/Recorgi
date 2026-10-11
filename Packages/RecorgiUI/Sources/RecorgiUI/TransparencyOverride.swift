import SwiftUI
import RecorgiCore

/// SwiftUI's own `accessibilityReduceTransparency` environment value is
/// get-only in this SDK — apps can read the live system setting, but can't
/// override it via `.environment(_:_:)` the way `.tint()` or other
/// environment values can be. So instead of faking that key, this is a
/// separate key GlassCard reads directly: nil leaves GlassCard resolving
/// the real system accessibilityReduceTransparency to `.regular`/`.minimal`
/// (and keeps tracking it live if the user changes it while the app is
/// running); a non-nil value — including `.medium`, which the system
/// setting itself has no equivalent for — overrides it for this app only.
///
/// This only affects views that explicitly read it, like GlassCard — it
/// has no way to reach the native `.glass`/`.glassProminent` button bezels
/// scattered through the app, since those are rendered by the system and
/// only ever follow the real, systemwide Reduce Transparency setting.
private struct TransparencyOverrideKey: EnvironmentKey {
    static let defaultValue: TransparencyMode? = nil
}

extension EnvironmentValues {
    var transparencyOverride: TransparencyMode? {
        get { self[TransparencyOverrideKey.self] }
        set { self[TransparencyOverrideKey.self] = newValue }
    }
}
