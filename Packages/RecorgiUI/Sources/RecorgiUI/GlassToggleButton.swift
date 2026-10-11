import SwiftUI

/// The one on/off control used everywhere in Recorgi — a glass button that
/// fills in (.glassProminent) when on and stays plain (.glass) when off, so
/// every toggle and every action button in the app reads as one family
/// instead of a mix of native switches, plain icons, and glass pills.
struct GlassToggleButton: View {
    let title: String?
    let systemImage: String
    @Binding var isOn: Bool

    init(_ title: String? = nil, systemImage: String, isOn: Binding<Bool>) {
        self.title = title
        self.systemImage = systemImage
        self._isOn = isOn
    }

    var body: some View {
        Group {
            if isOn {
                toggle.buttonStyle(.glassProminent)
            } else {
                toggle.buttonStyle(.glass)
            }
        }
        .buttonBorderShape(.capsule)
        .hoverCursor()
    }

    private var toggle: some View {
        Toggle(isOn: $isOn) {
            if let title {
                Label(title, systemImage: systemImage)
            } else {
                // Fixed size so icon-only toggles (e.g. the two quick
                // controls in the transport bar) match regardless of how
                // wide each SF Symbol glyph naturally is.
                Image(systemName: systemImage)
                    .frame(width: 20, height: 20)
            }
        }
        .toggleStyle(.button)
    }
}
