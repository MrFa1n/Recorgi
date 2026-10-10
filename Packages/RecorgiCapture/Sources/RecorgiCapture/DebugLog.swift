import Foundation

/// Temporary diagnostic logging for the recording pipeline — writes plain
/// text lines to a file next to the recordings themselves, so failures can
/// be inspected directly instead of relying on relaying UI text back and
/// forth. Remove once the recording-corruption investigation is closed.
@MainActor
enum DebugLog {
    static var fileURL: URL?

    static func write(_ message: String) {
        guard let fileURL else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            }
        } else {
            try? data.write(to: fileURL)
        }
    }
}
