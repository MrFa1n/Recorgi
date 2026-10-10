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
            // LazyVStack, not VStack: with dozens/hundreds of recordings,
            // an eager VStack renders every card's .glassEffect() (Liquid
            // Glass's blur/refraction material is expensive) at once, in
            // the whole list, not just what's on screen — the direct cause
            // of scroll lag. Lazy loading only materializes visible rows.
            LazyVStack(alignment: .leading, spacing: 20) {
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
                                RecordingThumbnailView(url: recording.url)

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
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                                .help("Показать в Finder")

                                Button {
                                    NSWorkspace.shared.open(recording.url)
                                } label: {
                                    Image(systemName: "play.fill")
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.glassProminent)
                                .buttonBorderShape(.capsule)
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

    // Shared, not instantiated per row per render — RelativeDateTimeFormatter
    // construction isn't free, and this used to run on every visible card on
    // every re-render.
    private static let relativeDateFormatter = RelativeDateTimeFormatter()

    private func detail(for recording: RecordingFile) -> String {
        let sizeString = ByteCountFormatter.string(fromByteCount: recording.sizeBytes, countStyle: .file)
        guard let date = recording.createdAt else { return sizeString }
        return "\(Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())) · \(sizeString)"
    }
}
