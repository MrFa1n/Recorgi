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
        // Empty, not removed: an unset navigationTitle falls back to the
        // app/bundle name anyway, which is still "Recorgi" — this is what
        // actually clears the window-title-bar text on every page (it's
        // the sidebar's title that NavigationSplitView shows up top,
        // regardless of which page is selected). The styled wordmark-font
        // "Recorgi" headline on the record page is the real title now.
        .navigationTitle("")
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
