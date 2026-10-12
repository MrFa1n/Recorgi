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

// A plain top-level constant, not a static member of the View struct: a
// static let there is implicitly MainActor-isolated (same isolation as
// the View itself), which the Sendable closure onGeometryChange(of:)
// takes can't reference. This has no isolation to begin with, so it's
// fine from either context.
private let recordingsScrollCoordinateSpace = "recordingsScroll"

struct RecordingsLibraryView: View {
    let saveDirectory: URL
    @State private var recordings: [RecordingFile] = []
    @State private var searchText = ""
    @State private var sortOrder: RecordingSortOrder = .dateDescending
    @State private var groupByDate = true
    @State private var renamingID: URL?
    @State private var renameDraft = ""
    @State private var renameError: String?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<URL> = []
    // The last item explicitly clicked (not one swept in by a shift-click
    // range) — the anchor a following shift-click extends from, same as
    // Finder/Mail.
    @State private var lastSelectedID: URL?
    @State private var pendingDelete: [RecordingFile]?
    @State private var deleteError: String?
    // Whether the controls row (with its "Удалить" button, while
    // selecting) is still at least partly visible — tracked so the
    // floating bottom-trailing delete button only shows up once it's
    // scrolled out of view, not permanently alongside it.
    @State private var isControlsRowVisible = true
    @Environment(\.accentTint) private var accentTint
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
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(recordingsScrollCoordinateSpace)) }) { _, newFrame in
                        isControlsRowVisible = newFrame.maxY > 0
                    }

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
            // Extra bottom clearance for the floating TransportBar — see
            // GeneralSettingsView's own comment on this same line.
            .padding(.bottom, 76)
            // maxHeight too — see GeneralSettingsView's own comment on
            // this same line: ScrollView centers short content vertically
            // by default on macOS, which could let a card drift down
            // under the floating TransportBar.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .coordinateSpace(name: recordingsScrollCoordinateSpace)
        // Fixed relative to the ScrollView's own (non-scrolling) bounds —
        // not inside the scrolling content — so it stays put at the
        // bottom-trailing corner as the list scrolls underneath it, same
        // technique ContentView uses to float TransportBar over each page.
        .overlay(alignment: .bottomTrailing) {
            floatingActionBar
                .animation(.easeOut(duration: 0.2), value: isControlsRowVisible)
                .animation(.easeOut(duration: 0.2), value: isSelecting)
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
        .alert("Ошибка", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("ОК", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(deleteConfirmationButtonLabel, role: .destructive) {
                performDelete()
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Файлы переместятся в Корзину — их можно будет восстановить оттуда.")
        }
        .sheet(item: $editingRecording) { recording in
            RecordingEditorView(recording: recording, onExported: refresh)
                // Plain .sheet() sizes itself once from the content's ideal
                // frame and doesn't let the user drag-resize it at all.
                // .fitted.sticky(...) (tried first) only actually freed up
                // width — .fitted keeps re-deriving its "fitted" size from
                // the content's own layout, and this sheet's height is
                // dominated by a ScrollView with no stable ideal height of
                // its own to latch onto, so it kept winning over the user's
                // vertical drag. .automatic doesn't fight a manual resize
                // the same way; .sticky(...) is what actually turns
                // dragging on (and remembers the chosen size) per axis.
                .presentationSizing(.automatic.sticky(horizontal: true, vertical: true))
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Text(selectedIDs.isEmpty ? "Выбери записи для удаления" : "Выбрано: \(selectedIDs.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Удалить", systemImage: "trash") {
                    pendingDelete = recordings.filter { selectedIDs.contains($0.id) }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .tint(.red)
                .disabled(selectedIDs.isEmpty)
                .hoverCursor()

                Button("Готово") {
                    endSelecting()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .hoverCursor()
            } else {
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
                        .hoverCursor()
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
                .hoverCursor()

                GlassToggleButton("По дате", systemImage: "calendar.day.timeline.left", isOn: $groupByDate)

                Spacer()

                Button("Выбрать") {
                    isSelecting = true
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .hoverCursor()
                .disabled(recordings.isEmpty)

                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .hoverCursor()
                .help("Обновить список записей")
            }
        }
    }

    /// Stand-in for the controls row's trailing action button(s) once
    /// that's scrolled out of view — same actions, just reachable without
    /// scrolling back up. Not selecting yet: a single "Выбрать" entry
    /// point, so starting a multi-select never needs a trip back to the
    /// top — every row on screen already grows a checkbox the instant
    /// isSelecting flips true, right where you're currently looking.
    /// Already selecting: "Удалить" (with the running count) plus a
    /// compact "done" button to back out, mirroring the top row's pair.
    @ViewBuilder
    private var floatingActionBar: some View {
        if !isControlsRowVisible {
            HStack(spacing: 8) {
                if isSelecting {
                    Button {
                        pendingDelete = recordings.filter { selectedIDs.contains($0.id) }
                    } label: {
                        Label("Удалить (\(selectedIDs.count))", systemImage: "trash")
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.red)
                    .disabled(selectedIDs.isEmpty)
                    .hoverCursor()

                    Button {
                        endSelecting()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .hoverCursor()
                    .help("Готово")
                } else {
                    Button("Выбрать") {
                        isSelecting = true
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .hoverCursor()
                    .help("Выбрать несколько записей для удаления")
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func row(for recording: RecordingFile) -> some View {
        let isSelected = selectedIDs.contains(recording.id)
        GlassCard {
            HStack {
                if isSelecting {
                    Button {
                        selectTapped(recording)
                    } label: {
                        Group {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .themedTint()
                    .hoverCursor()
                }

                RecordingThumbnailView(url: recording.url)

                VStack(alignment: .leading, spacing: 4) {
                    if renamingID == recording.id {
                        ThemedRenameField(
                            text: $renameDraft,
                            tint: accentTint.map(NSColor.init) ?? .controlAccentColor,
                            onCommit: { commitRename(recording) },
                            onCancel: { renamingID = nil }
                        )
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

                if !isSelecting {
                    Button {
                        beginRename(recording)
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .hoverCursor()
                    .help("Переименовать")

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
                    } label: {
                        Image(systemName: "folder")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .hoverCursor()
                    .help("Показать в Finder")

                    Button {
                        pendingDelete = [recording]
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .hoverCursor()
                    .help("Удалить")

                    Button {
                        editingRecording = recording
                    } label: {
                        Image(systemName: "play.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .themedTint()
                    .hoverCursor()
                    .help("Открыть во встроенном плеере")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                selectTapped(recording)
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

    // MARK: - Selection & delete

    /// The currently visible recordings in on-screen order (grouped +
    /// sorted + searched) — the sequence a shift-click range is measured
    /// across, same list the rows themselves are drawn from.
    private var flatRecordings: [RecordingFile] {
        sections.flatMap { $0.items }
    }

    /// Plain click: toggle just this one. Shift-click: extend/add the
    /// whole range from the last explicitly-clicked item to this one,
    /// same as Finder/Mail — lets you pick a start, scroll, shift-click an
    /// end, and get everything between without clicking each one.
    private func selectTapped(_ recording: RecordingFile) {
        if NSEvent.modifierFlags.contains(.shift),
           let anchor = lastSelectedID,
           let anchorIndex = flatRecordings.firstIndex(where: { $0.id == anchor }),
           let targetIndex = flatRecordings.firstIndex(where: { $0.id == recording.id }) {
            let range = anchorIndex <= targetIndex ? anchorIndex...targetIndex : targetIndex...anchorIndex
            for item in flatRecordings[range] {
                selectedIDs.insert(item.id)
            }
        } else {
            toggleSelection(recording)
        }
        lastSelectedID = recording.id
    }

    private func toggleSelection(_ recording: RecordingFile) {
        if selectedIDs.contains(recording.id) {
            selectedIDs.remove(recording.id)
        } else {
            selectedIDs.insert(recording.id)
        }
    }

    private func endSelecting() {
        isSelecting = false
        selectedIDs.removeAll()
        lastSelectedID = nil
    }

    private var deleteConfirmationTitle: String {
        guard let pendingDelete else { return "" }
        if pendingDelete.count == 1 {
            return "Удалить «\(pendingDelete[0].name)»?"
        }
        return "Удалить \(pendingDelete.count) записей?"
    }

    private var deleteConfirmationButtonLabel: String {
        guard let pendingDelete, pendingDelete.count > 1 else { return "Удалить" }
        return "Удалить (\(pendingDelete.count))"
    }

    private func performDelete() {
        guard let targets = pendingDelete else { return }
        pendingDelete = nil
        for recording in targets {
            do {
                try library.delete(recording)
            } catch {
                // Keep going on a multi-delete even if one file fails (e.g.
                // it was already moved/deleted outside the app) — report
                // the last failure rather than stopping after the first.
                deleteError = error.localizedDescription
            }
        }
        selectedIDs.subtract(targets.map(\.id))
        if isSelecting && selectedIDs.isEmpty {
            endSelecting()
        }
        refresh()
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
