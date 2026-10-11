import SwiftUI
import RecorgiCore

/// Shared card container for detail-page content — a rounded glass panel,
/// mirroring how system apps (News, Music) float content on glass cards
/// instead of flat colored boxes.
///
/// Three degrees, not just on/off (see TransparencyMode): `.regular` is
/// the full Liquid Glass look this always used; `.medium` swaps it for a
/// plain SwiftUI Material, which has no Liquid Glass blur but is still
/// translucent; `.minimal` is a flat, fully opaque fill. `.medium` and
/// `.minimal` both draw an explicit hairline border, because the glass
/// effect's own rendering is what gives `.regular` its visible edge —
/// without it, a plain Material or solid fill of nearly the same color as
/// the window behind it had no boundary at all and the card effectively
/// disappeared.
struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.transparencyOverride) private var transparencyOverride

    private var level: TransparencyMode {
        transparencyOverride ?? (systemReduceTransparency ? .minimal : .regular)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20)
        let padded = content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

        switch level {
        case .regular:
            padded.glassEffect(in: shape)
        case .medium:
            padded
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.separator, lineWidth: 1))
        case .minimal:
            padded
                .background(.background, in: shape)
                .overlay(shape.strokeBorder(.separator, lineWidth: 1))
        }
    }
}
