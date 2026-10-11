import AVFoundation
import AppKit
import RecorgiCore

/// Generates and caches small preview thumbnails for recorded .mov files,
/// for the Recordings library list — so a long list of similarly-named
/// files is actually scannable at a glance instead of just timestamps.
public actor RecordingThumbnailLoader {
    public static let shared = RecordingThumbnailLoader()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 300
    }

    public func thumbnail(for url: URL, maxPixelSize: CGFloat = 240) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

        // A moment in, not exactly zero — the very first frame of a
        // recording can be black or an incomplete keyframe before the
        // encoder settles.
        let time = CMTime(seconds: 0.3, preferredTimescale: 600)

        guard let result = try? await generator.image(at: time) else {
            Log.library.debug("RecordingThumbnailLoader: image generation failed for \(url.lastPathComponent, privacy: .public)")
            return nil
        }

        let image = NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
