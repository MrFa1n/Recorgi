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
        if isOn {
            toggle.buttonStyle(.glassProminent)
        } else {
            toggle.buttonStyle(.glass)
        }
    }

    private var toggle: some View {
        Toggle(isOn: $isOn) {
            if let title {
                Label(title, systemImage: systemImage)
            } else {
                Image(systemName: systemImage)
            }
        }
        .toggleStyle(.button)
    }
}
