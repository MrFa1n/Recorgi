import Foundation
import RecorgiCore

public struct RecordingFile: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let createdAt: Date?
    public let sizeBytes: Int64

    public var id: URL { url }

    /// The public movie is ready for playback; the editor prefers the
    /// untouched multitrack original stored beside it when available.
    public var editingURL: URL {
        let source = Self.sourceURL(for: url)
        return FileManager.default.fileExists(atPath: source.path) ? source : url
    }

    public var hasEditingSource: Bool { editingURL != url }

    public static func sourcesDirectory(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent) — исходники", isDirectory: true)
    }

    public static func sourceURL(for url: URL) -> URL {
        sourcesDirectory(for: url).appendingPathComponent("Original").appendingPathExtension(url.pathExtension)
    }
}

public enum RecordingRenameError: LocalizedError {
    case emptyName
    case alreadyExists
    case renameFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Название не может быть пустым."
        case .alreadyExists: return "Запись с таким названием уже существует."
        case .renameFailed(let reason): return "Не удалось переименовать: \(reason)"
        }
    }
}

public enum RecordingDeleteError: LocalizedError {
    case deleteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .deleteFailed(let reason): return "Не удалось удалить: \(reason)"
        }
    }
}

/// Lists the recording files Recorgi has written to a save directory, for
/// the "Recordings" library page.
public struct RecordingLibrary: Sendable {
    // Derived from VideoContainer.allCases, not hardcoded to "mov" — a
    // recording's extension depends on the container the user had selected
    // at record time (see RecordingSettings.videoContainer), which can be
    // .mp4. A fixed "mov"-only filter here once silently hid every .mp4
    // recording from the library — found when a user reported a file they
    // could see in Finder just not showing up in-app.
    private static let recordingExtensions = Set(VideoContainer.allCases.map { $0.fileExtension.lowercased() })

    public init() {}

    public func recordings(in directory: URL) -> [RecordingFile] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            Log.library.error("recordings(in:): could not list contents of save directory")
            return []
        }

        return entries
            .filter { Self.recordingExtensions.contains($0.pathExtension.lowercased()) }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return RecordingFile(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    createdAt: values?.contentModificationDate,
                    sizeBytes: Int64(values?.fileSize ?? 0)
                )
            }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// Renames a recording's file on disk, keeping its extension. "/" is
    /// stripped from the requested name — left as-is, it would be read as
    /// a path separator by appendingPathComponent and could move the file
    /// into (or, with "..", out of) a different directory than the one
    /// it's actually in.
    @discardableResult
    public func rename(_ recording: RecordingFile, to newBaseName: String) throws -> RecordingFile {
        let sanitized = newBaseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !sanitized.isEmpty, sanitized != ".", sanitized != ".." else {
            throw RecordingRenameError.emptyName
        }
        guard sanitized != recording.name else { return recording }

        let newURL = recording.url
            .deletingLastPathComponent()
            .appendingPathComponent(sanitized)
            .appendingPathExtension(recording.url.pathExtension)

        let sourcesURL = RecordingFile.sourcesDirectory(for: recording.url)
        let newSourcesURL = RecordingFile.sourcesDirectory(for: newURL)
        let hasSources = FileManager.default.fileExists(atPath: sourcesURL.path)
        guard !FileManager.default.fileExists(atPath: newURL.path),
              !FileManager.default.fileExists(atPath: newSourcesURL.path) else {
            throw RecordingRenameError.alreadyExists
        }

        do {
            if hasSources {
                try FileManager.default.moveItem(at: sourcesURL, to: newSourcesURL)
            }
            do {
                try FileManager.default.moveItem(at: recording.url, to: newURL)
            } catch {
                if hasSources {
                    do { try FileManager.default.moveItem(at: newSourcesURL, to: sourcesURL) }
                    catch { Log.library.error("rename(): source rollback failed: \(error.localizedDescription, privacy: .public)") }
                }
                throw error
            }
            Log.library.notice("rename(): ok, includedSources=\(hasSources, privacy: .public)")
        } catch {
            Log.library.error("rename(): moveItem failed: \(error.localizedDescription, privacy: .public)")
            throw RecordingRenameError.renameFailed(error.localizedDescription)
        }

        let values = try? newURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return RecordingFile(
            url: newURL,
            name: sanitized,
            createdAt: values?.contentModificationDate ?? recording.createdAt,
            sizeBytes: Int64(values?.fileSize ?? Int(recording.sizeBytes))
        )
    }

    /// Moves a recording to the Trash rather than permanently deleting it —
    /// reversible if this turns out to be a mistake, same safety margin
    /// Finder's own Delete gives you.
    public func delete(_ recording: RecordingFile) throws {
        let sourcesURL = RecordingFile.sourcesDirectory(for: recording.url)
        var trashedSources: NSURL?
        do {
            if FileManager.default.fileExists(atPath: sourcesURL.path) {
                try FileManager.default.trashItem(at: sourcesURL, resultingItemURL: &trashedSources)
            }
            do {
                try FileManager.default.trashItem(at: recording.url, resultingItemURL: nil)
            } catch {
                if let trashedSources {
                    do { try FileManager.default.moveItem(at: trashedSources as URL, to: sourcesURL) }
                    catch { Log.library.error("delete(): source rollback failed: \(error.localizedDescription, privacy: .public)") }
                }
                throw error
            }
            Log.library.notice("delete(): moved movie and any editing sources to Trash")
        } catch {
            Log.library.error("delete(): trashItem failed: \(error.localizedDescription, privacy: .public)")
            throw RecordingDeleteError.deleteFailed(error.localizedDescription)
        }
    }
}
