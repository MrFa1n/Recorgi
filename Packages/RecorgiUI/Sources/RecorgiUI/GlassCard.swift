import SwiftUI

/// Shared card container for detail-page content — a rounded glass panel,
/// mirroring how system apps (News, Music) float content on glass cards
/// instead of flat colored boxes.
struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: RoundedRectangle(cornerRadius: 20))
    }
}
