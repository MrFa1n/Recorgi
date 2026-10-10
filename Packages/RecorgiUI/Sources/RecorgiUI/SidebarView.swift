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
                row(.audioSources)
                row(.general)
            }
        }
        .listStyle(.sidebar)
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
