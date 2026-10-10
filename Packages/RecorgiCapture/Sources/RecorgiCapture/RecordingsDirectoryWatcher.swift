import Foundation

/// Watches a directory for additions/removals/renames (not file-content
/// writes) and calls back — so the Recordings library picks up changes made
/// in Finder, or by another process, without a manual refresh.
public final class RecordingsDirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pendingWorkItem: DispatchWorkItem?

    public init() {}

    public func start(watching directory: URL, onChange: @escaping @MainActor () -> Void) {
        stop()

        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            // A single Finder operation (e.g. deleting several files) can
            // fire several write events back to back — coalesce them so a
            // burst doesn't re-scan (and re-sort/re-filter) the whole list
            // several times in a row.
            self?.pendingWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                MainActor.assumeIsolated {
                    onChange()
                }
            }
            self?.pendingWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
    }

    public func stop() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        source?.cancel()
        source = nil
    }

    deinit {
        pendingWorkItem?.cancel()
        source?.cancel()
    }
}
