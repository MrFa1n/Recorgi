import SwiftUI
import AppKit
import RecorgiCore
import RecorgiCapture

struct RecordingsLibraryView: View {
    let saveDirectory: URL
    @State private var recordings: [RecordingFile] = []

    private let library = RecordingLibrary()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Записи")
                    .font(.largeTitle.bold())

                if recordings.isEmpty {
                    GlassCard {
                        Text("Пока нет записей. Начни запись — файлы появятся здесь.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(recordings) { recording in
                        GlassCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recording.name)
                                        .font(.headline)
                                    Text(detail(for: recording))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([recording.url])
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.glass)
                                .help("Показать в Finder")

                                Button {
                                    NSWorkspace.shared.open(recording.url)
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .buttonStyle(.glassProminent)
                                .help("Воспроизвести")
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: saveDirectory) {
            recordings = library.recordings(in: saveDirectory)
        }
    }

    private func detail(for recording: RecordingFile) -> String {
        let sizeString = ByteCountFormatter.string(fromByteCount: recording.sizeBytes, countStyle: .file)
        guard let date = recording.createdAt else { return sizeString }
        let formatter = RelativeDateTimeFormatter()
        return "\(formatter.localizedString(for: date, relativeTo: Date())) · \(sizeString)"
    }
}
