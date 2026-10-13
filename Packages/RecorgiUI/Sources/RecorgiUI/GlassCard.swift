import SwiftUI

/// Shared card container for detail-page content — a rounded glass panel,
/// mirroring how system apps (News, Music) float content on glass cards
/// instead of flat colored boxes.
///
/// Deliberately just `.recorgiGlass()` with no app-level transparency
/// setting of our own: the system's own Liquid Glass slider (System
/// Settings > Appearance) and its Reduce Transparency accessibility
/// setting already drive how translucent this renders, automatically and
/// live — a custom override here would only fight that rather than add
/// anything. See GlassCompatibility.swift for the macOS 15-25 fallback.
struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .recorgiGlass(in: RoundedRectangle(cornerRadius: 20))
    }
}
