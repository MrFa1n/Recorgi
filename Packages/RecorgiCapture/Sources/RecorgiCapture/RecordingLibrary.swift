import Foundation
import RecorgiCore

public struct RecordingFile: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let createdAt: Date?
    public let sizeBytes: Int64

    public var id: URL { url }
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

/// Lists the .mov files Recorgi has written to a save directory, for the
/// "Recordings" library page.
public struct RecordingLibrary: Sendable {
    public init() {}

    public func recordings(in directory: URL) -> [RecordingFile] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { $0.pathExtension.lowercased() == "mov" }
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

        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw RecordingRenameError.alreadyExists
        }

        do {
            try FileManager.default.moveItem(at: recording.url, to: newURL)
        } catch {
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
}
