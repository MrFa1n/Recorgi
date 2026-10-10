/// What system audio to capture when system-audio recording is on.
public enum SystemAudioScope: Hashable, Sendable {
    case entireSystem
    case application(AudioApplication)
}
