import Foundation

public enum RecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording(startedAt: Date)
    case stopping
}
