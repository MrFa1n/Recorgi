import SwiftUI
import RecorgiCapture

/// Small preview thumbnail for one recording — loads asynchronously via
/// RecordingThumbnailLoader (cached, so revisiting the library is instant)
/// and shows a placeholder while loading or if generation fails.
struct RecordingThumbnailView: View {
    let url: URL

    private let width: CGFloat = 72
    private let height: CGFloat = 44

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.15))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
        .task(id: url) {
            image = await RecordingThumbnailLoader.shared.thumbnail(for: url)
        }
    }
}
