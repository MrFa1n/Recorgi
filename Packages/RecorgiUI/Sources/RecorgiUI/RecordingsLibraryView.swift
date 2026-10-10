import SwiftUI
import AppKit
import RecorgiCore
import RecorgiCapture

private enum RecordingSortOrder: String, CaseIterable, Identifiable {
    case dateDescending, dateAscending, nameAscending, nameDescending, sizeDescending, sizeAscending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dateDescending: return "Сначала новые"
        case .dateAscending: return "Сначала старые"
        case .nameAscending: return "Имя (А→Я)"
        case .nameDescending: return "Имя (Я→А)"
        case .sizeDescending: return "Сначала большие"
        case .sizeAscending: return "Сначала маленькие"
        }
    }

    var systemImage: String {
        switch self {
        case .dateDescending, .dateAscending: return "calendar"
        case .nameAscending, .nameDescending: return "textformat"
        case .sizeDescending, .sizeAscending: return "arrow.up.arrow.down.circle"
        }
    }
}

private struct RecordingSection: Identifiable {
    let label: String
    let items: [RecordingFile]
    var id: String { label }
}

struct RecordingsLibraryView: View {
    let saveDirectory: URL
    @State private var recordings: [RecordingFile] = []
    @State private var searchText = ""
    @State private var sortOrder: RecordingSortOrder = .dateDescending
    @State private var groupByDate = true
    @State private var renamingID: URL?
    @State private var renameDraft = ""
    @State private var renameError: String?
    @FocusState private var renameFieldFocused: Bool
    // @State, not `let` — same reason as CaptureRegionView's AreaHighlighter:
    // SwiftUI recreates this View struct on every re-render, and a plain
    // `let` would silently spawn a fresh, unstarted watcher each time.
    @State private var watcher = RecordingsDirectoryWatcher()
    @State private var editingRecording: RecordingFile?

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

                controls

                if recordings.isEmpty {
                    GlassCard {
                        Text("Пока нет записей. Начни запись — файлы появятся здесь.")
                            .foregroundStyle(.secondary)
                    }
                } else if sections.isEmpty {
                    GlassCard {
                        Text("Ничего не найдено по запросу «\(searchText)».")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(sections) { section in
                        if groupByDate {
                            Text(section.label)
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }

                        ForEach(section.items) { recording in
                            row(for: recording)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: saveDirectory) {
            refresh()
            watcher.start(watching: saveDirectory) {
                refresh()
            }
        }
        .onDisappear {
            watcher.stop()
        }
        .alert("Ошибка", isPresented: Binding(
            get: { renameError != nil },
            set: { if !$0 { renameError = nil } }
        )) {
            Button("ОК", role: .cancel) { renameError = nil }
        } message: {
            Text(renameError ?? "")
        }
        .sheet(item: $editingRecording) { recording in
            RecordingEditorView(recording: recording, onExported: refresh)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Поиск по названию", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(in: Capsule())
            .frame(maxWidth: 320)

            Menu {
                ForEach(RecordingSortOrder.allCases) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        Label(order.label, systemImage: order.systemImage)
                    }
                }
            } label: {
                Label(sortOrder.label, systemImage: sortOrder.systemImage)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)

            GlassToggleButton("По дате", systemImage: "calendar.day.timeline.left", isOn: $groupByDate)

            Spacer()

            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .help("Обновить список записей")
        }
    }

    @ViewBuilder
    private func row(for recording: RecordingFile) -> some View {
        GlassCard {
            HStack {
                RecordingThumbnailView(url: recording.url)

                VStack(alignment: .leading, spacing: 4) {
                    if renamingID == recording.id {
                        TextField("Название записи", text: $renameDraft)
                            .textFieldStyle(.plain)
                            .font(.headline)
                            .focused($renameFieldFocused)
                            .onSubmit { commitRename(recording) }
                            .onKeyPress(.escape) { renamingID = nil; return .handled }
                            .onAppear { renameFieldFocused = true }
                    } else {
                        Text(recording.name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Text(detail(for: recording))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    beginRename(recording)
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .help("Переименовать")

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
                    editingRecording = recording
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .help("Открыть во встроенном плеере")
            }
        }
    }

    // MARK: - Filtering, sorting, grouping

    private var filteredRecordings: [RecordingFile] {
        guard !searchText.isEmpty else { return recordings }
        return recordings.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var sections: [RecordingSection] {
        guard groupByDate else {
            return [RecordingSection(label: "", items: sorted(filteredRecordings))]
        }
        // Bucketed in date-descending order regardless of sortOrder, so
        // section headers always read chronologically (Today, Yesterday, …)
        // — sortOrder only reorders items *within* each section.
        let dateOrdered = filteredRecordings.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        var order: [String] = []
        var buckets: [String: [RecordingFile]] = [:]
        for item in dateOrdered {
            let label = Self.groupLabel(for: item.createdAt)
            if buckets[label] == nil {
                buckets[label] = []
                order.append(label)
            }
            buckets[label]?.append(item)
        }
        return order.map { label in RecordingSection(label: label, items: sorted(buckets[label] ?? [])) }
    }

    private func sorted(_ items: [RecordingFile]) -> [RecordingFile] {
        switch sortOrder {
        case .dateDescending:
            return items.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .dateAscending:
            return items.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        case .nameAscending:
            return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDescending:
            return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .sizeDescending:
            return items.sorted { $0.sizeBytes > $1.sizeBytes }
        case .sizeAscending:
            return items.sorted { $0.sizeBytes < $1.sizeBytes }
        }
    }

    private static func groupLabel(for date: Date?) -> String {
        guard let date else { return "Без даты" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return "На этой неделе"
        }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .month) {
            return "В этом месяце"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    private func refresh() {
        recordings = library.recordings(in: saveDirectory)
    }

    // MARK: - Rename

    private func beginRename(_ recording: RecordingFile) {
        renameDraft = recording.name
        renamingID = recording.id
    }

    private func commitRename(_ recording: RecordingFile) {
        renamingID = nil
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != recording.name, !trimmed.isEmpty else { return }
        do {
            let updated = try library.rename(recording, to: trimmed)
            if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
                recordings[index] = updated
            }
        } catch {
            renameError = error.localizedDescription
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
