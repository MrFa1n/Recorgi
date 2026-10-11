import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSection?

    var body: some View {
        List(selection: $selection) {
            Section {
                row(.record)
            }
            Section("Библиотека") {
                row(.recordings)
            }
            Section("Настройки") {
                row(.captureRegion)
                row(.audioSources)
                row(.general)
            }
        }
        .listStyle(.sidebar)
        // The system's default sidebar material is the older vibrancy
        // effect (NSVisualEffectView under the hood), not Liquid Glass —
        // it doesn't track System Settings > Appearance's Liquid Glass
        // slider. Hiding the List's own background and drawing a real
        // .glassEffect() rectangle behind it instead makes the sidebar
        // react to that slider live, same as every GlassCard elsewhere.
        .scrollContentBackground(.hidden)
        .background {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: Rectangle())
        }
        .navigationTitle("Recorgi")
    }

    private func row(_ section: SidebarSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.systemImage)
                .foregroundStyle(section.tint)
        }
        .tag(section)
    }
}
