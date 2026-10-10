import Foundation

public enum RecordingState: Equatable, Sendable {
    case idle
    case recording(startedAt: Date)
    case stopping
}
