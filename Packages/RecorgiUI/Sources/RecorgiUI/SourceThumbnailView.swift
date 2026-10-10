import SwiftUI
import RecorgiCapture

/// A real, live screenshot of a display or window — used throughout the
/// capture-region picker so choosing a source shows what's actually on it,
/// not a generic icon. Loads asynchronously per `source` and shows a
/// placeholder while loading or if the capture fails (e.g. a window that
/// closed between listing and loading).
struct SourceThumbnailView: View {
    enum Source: Equatable {
        case display(UInt32)
        case window(UInt32)
    }

    let source: Source
    var aspectRatio: CGFloat = 16.0 / 10.0

    @State private var image: NSImage?

    private let loader = CaptureThumbnailLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.3))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: source) {
            image = await load()
        }
    }

    private func load() async -> NSImage? {
        switch source {
        case .display(let id): return await loader.thumbnail(forDisplay: id)
        case .window(let id): return await loader.thumbnail(forWindow: id)
        }
    }
}
