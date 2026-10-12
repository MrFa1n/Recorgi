import Foundation

/// A constant-gain window on one audio track's timeline — "boost this part,
/// lower that part". `gain` is a linear multiplier matched to
/// AVAudioMixInputParameters' own scale: 1.0 = unchanged, 2.0 = roughly
/// +6dB, 0.0 = silent.
public struct AudioVolumeRegion: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var startSeconds: Double
    public var endSeconds: Double
    public var gain: Double

    public init(id: UUID = UUID(), startSeconds: Double, endSeconds: Double, gain: Double) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.gain = gain
    }
}

/// One audio track's volume plan for the in-app editor: an overall gain
/// applied everywhere, plus any number of region overrides for specific
/// stretches of the recording. Both the live preview player and the final
/// export (VideoEditExporter) turn this into the same AVMutableAudioMix, so
/// what's heard while editing matches what gets saved.
public struct AudioTrackVolume: Hashable, Sendable {
    public var baseGain: Double
    public var regions: [AudioVolumeRegion]

    public init(baseGain: Double = 1.0, regions: [AudioVolumeRegion] = []) {
        self.baseGain = baseGain
        self.regions = regions
    }
}
