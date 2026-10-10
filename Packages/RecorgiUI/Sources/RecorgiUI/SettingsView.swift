import SwiftUI
import AppKit
import RecorgiCore
import RecorgiCapture

public struct SettingsView: View {
    @ObservedObject var settings: RecordingSettings
    @State private var microphones: [AudioInputDevice] = []

    private let deviceProvider = AudioDeviceProvider()

    public init(settings: RecordingSettings) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section("Аудио") {
                Toggle("Записывать системный звук", isOn: $settings.isSystemAudioEnabled)
                Toggle("Записывать микрофон", isOn: $settings.isMicrophoneEnabled)

                Picker("Микрофон", selection: $settings.selectedMicrophoneID) {
                    Text("По умолчанию").tag(String?.none)
                    ForEach(microphones) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .disabled(!settings.isMicrophoneEnabled)
            }

            Section("Сохранение") {
                HStack {
                    Text(settings.saveDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Изменить…") {
                        chooseSaveDirectory()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420, height: 260)
        .onAppear {
            microphones = deviceProvider.availableMicrophones()
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
