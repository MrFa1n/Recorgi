import Foundation
import RecorgiCore

public struct RecordingFile: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let createdAt: Date?
    public let sizeBytes: Int64

    public var id: URL { url }
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
}
