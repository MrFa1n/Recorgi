import Foundation

public enum RecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording(startedAt: Date)
    case pausing
    /// `startedAt` is the same anchor `.recording` carries — on resume it
    /// gets shifted forward by however long the pause lasted, so
    /// `Date().timeIntervalSince(startedAt)` keeps meaning "elapsed
    /// recording time" across any number of pause/resume cycles without
    /// the UI needing to track paused duration itself. `pausedAt` is just
    /// the moment this pause began, so the UI can show a frozen elapsed
    /// time (`pausedAt - startedAt`) instead of one that keeps ticking.
    case paused(startedAt: Date, pausedAt: Date)
    case resuming
    case stopping
}
