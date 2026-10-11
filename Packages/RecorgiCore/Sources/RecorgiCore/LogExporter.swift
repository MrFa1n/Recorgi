import Foundation
import OSLog

/// Reads back everything Recorgi has logged (via `Log`, see Log.swift) and
/// formats it as plain text, ready to save to a file.
///
/// Deliberately scoped to `.currentProcessIdentifier`, not `.system`:
/// `OSLogStore`'s system-wide scope needs the calling process to run as an
/// admin (see `OSLogStore.local()`'s own documentation), which isn't a
/// permission this app should ever need or ask for. The tradeoff is this
/// only covers the current run — if something went wrong in a *previous*
/// launch, export right after it happens, before quitting, rather than
/// expecting to pull it up later.
public enum LogExporter {
    public enum ExportError: LocalizedError {
        case storeUnavailable(String)

        public var errorDescription: String? {
            switch self {
            case .storeUnavailable(let reason):
                return "Could not read the log: \(reason)"
            }
        }
    }

    public static func export() throws -> String {
        let store: OSLogStore
        do {
            store = try OSLogStore(scope: .currentProcessIdentifier)
        } catch {
            throw ExportError.storeUnavailable(error.localizedDescription)
        }

        // Only our own subsystem — the current process also runs plenty of
        // framework code (AVFoundation, ScreenCaptureKit, …) that logs
        // under its own subsystems, which would otherwise drown this out.
        let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)

        let entries: AnySequence<OSLogEntry>
        do {
            entries = try store.getEntries(matching: predicate)
        } catch {
            throw ExportError.storeUnavailable(error.localizedDescription)
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []
        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else { continue }
            lines.append("\(dateFormatter.string(from: logEntry.date)) [\(logEntry.level.label)] [\(logEntry.category)] \(logEntry.composedMessage)")
        }

        guard !lines.isEmpty else {
            return "No log entries yet this session."
        }
        return lines.joined(separator: "\n")
    }

    public static func suggestedFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Recorgi Log \(formatter.string(from: Date())).log"
    }
}

private extension OSLogEntryLog.Level {
    var label: String {
        switch self {
        case .undefined: return "?"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        @unknown default: return "?"
        }
    }
}
