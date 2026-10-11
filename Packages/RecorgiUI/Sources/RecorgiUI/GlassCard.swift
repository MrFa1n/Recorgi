import SwiftUI

/// Shared card container for detail-page content — a rounded glass panel,
/// mirroring how system apps (News, Music) float content on glass cards
/// instead of flat colored boxes.
///
/// Falls back to a solid, opaque card under Reduce Transparency (system or
/// app override — see TransparencyOverride.swift) instead of the blurred
/// glass background, matching how Reduce Transparency is meant to work
/// elsewhere in macOS: content stays laid out exactly the same, only the
/// material behind it changes.
struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.reduceTransparencyOverride) private var reduceTransparencyOverride

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20)
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if reduceTransparency {
                    shape.fill(.background)
                }
            }
            .glassEffect(reduceTransparency ? .identity : .regular, in: shape)
    }
}
