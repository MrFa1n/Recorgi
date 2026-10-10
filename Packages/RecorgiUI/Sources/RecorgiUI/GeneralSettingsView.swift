import SwiftUI
import AppKit
import RecorgiCore

struct GeneralSettingsView: View {
    @ObservedObject var settings: RecordingSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Основные")
                    .font(.largeTitle.bold())

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Папка для записей", systemImage: "folder.fill")
                            .font(.headline)

                        HStack {
                            Text(settings.saveDirectory.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Изменить…") {
                                chooseSaveDirectory()
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url
        }
    }
}
