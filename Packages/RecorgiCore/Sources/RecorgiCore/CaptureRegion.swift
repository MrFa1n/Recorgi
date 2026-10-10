import CoreGraphics

/// What video to capture. Mirrors SystemAudioScope's shape (an explicit
/// "default" case plus specific picks) so the two selection UIs feel
/// consistent.
public enum CaptureRegion: Hashable, Sendable {
    case primaryDisplay
    case display(DisplayInfo)
    case window(WindowInfo)
    case area(DisplayInfo, CGRect)
}
