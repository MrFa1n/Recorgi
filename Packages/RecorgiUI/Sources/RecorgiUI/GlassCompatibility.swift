import SwiftUI

/// Carries the debug "show the pre-macOS-26 fallback UI" override down
/// through the view tree, same pattern as `accentTint` (see
/// AccentTint.swift) — a separate environment key rather than threading
/// `RecordingSettings` through every view that needs to style itself.
/// Wired once at the ContentView root from
/// `RecordingSettings.debugForceLegacyUI`; read by every modifier below.
private struct ForceLegacyUIKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var forceLegacyUI: Bool {
        get { self[ForceLegacyUIKey.self] }
        set { self[ForceLegacyUIKey.self] = newValue }
    }
}

/// The ONE place in RecorgiUI allowed to call the real Liquid Glass APIs
/// (`glassEffect`, `.buttonStyle(.glass/.glassProminent)`) — everything
/// else goes through `View.recorgiGlass(in:tint:)` and
/// `View.glassButtonStyle(prominent:)` below, which gate on
/// `#available(macOS 26, *)` (plus the debug override) and fall back to
/// an ordinary Material/bordered-button look otherwise. See CLAUDE.md's
/// "Backward compatibility" section for why this exists: the recording
/// engine itself only needs macOS 15, and raising the whole app's floor
/// to 26 just to get Liquid Glass unconditionally would throw that away.
private struct RecorgiGlassBackground<S: Shape>: ViewModifier {
    @Environment(\.forceLegacyUI) private var forceLegacyUI
    let shape: S
    let tint: Color?

    // Split into two single-expression helpers rather than branching
    // inline inside `body` — a nested if-let inside an if-#available
    // inside a @ViewBuilder, generic over Shape, was enough to make the
    // compiler give up with "failed to produce diagnostic for expression"
    // instead of a real error. Smaller, single-return functions sidestep
    // whatever inference blew up there.
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !forceLegacyUI {
            glassBody(content)
        } else {
            legacyBody(content)
        }
    }

    @available(macOS 26, *)
    private func glassBody(_ content: Content) -> some View {
        let glass: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
        return content.glassEffect(glass, in: shape)
    }

    // Material gives the same "floats above the desktop" read as Liquid
    // Glass without the real thing's live specular/bending behavior,
    // which simply doesn't exist pre-26 — closest approximation
    // available, not a different design language. Built up as separate
    // statements, not one long chained expression — chaining .background
    // twice plus a generic-Shape .overlay in a single expression is what
    // made the type-checker choke above.
    private func legacyBody(_ content: Content) -> some View {
        let tintOverlay: Color = tint?.opacity(0.18) ?? .clear
        let tinted = content.background(tintOverlay, in: shape)
        let materialized = tinted.background(.regularMaterial, in: shape)
        // .stroke, not .strokeBorder: the latter needs InsettableShape,
        // which would narrow the generic constraint above beyond plain
        // Shape for no visible gain at a 1pt hairline width.
        let border = shape.stroke(Color.primary.opacity(0.08), lineWidth: 1)
        return materialized.overlay(border)
    }
}

private struct RecorgiGlassButtonStyle: ViewModifier {
    @Environment(\.forceLegacyUI) private var forceLegacyUI
    let prominent: Bool

    // Not a ternary: .glass/.glassProminent (and .bordered/.borderedProminent)
    // are different concrete PrimitiveButtonStyle types, so each needs its
    // own buttonStyle(_:) call for the type-checker, not one call picking
    // between two values of mismatched type.
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !forceLegacyUI {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

extension View {
    /// Card/pill backgrounds — what `GlassCard` and the recordings-library
    /// pills are built from. Real Liquid Glass on macOS 26+, a Material
    /// panel below that.
    func recorgiGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(RecorgiGlassBackground(shape: shape, tint: tint))
    }

    /// Buttons — what `GlassToggleButton` and every plain action button in
    /// the app are built from. Real Liquid Glass on macOS 26+, the
    /// standard `.bordered`/`.borderedProminent` style below that. Always
    /// pair with `.buttonBorderShape(.capsule)` (works unchanged on both
    /// paths) for the app's usual pill shape.
    func glassButtonStyle(prominent: Bool = false) -> some View {
        modifier(RecorgiGlassButtonStyle(prominent: prominent))
    }
}
