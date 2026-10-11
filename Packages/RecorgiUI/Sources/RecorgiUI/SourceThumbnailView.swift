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

    /// Grid cards (displays, windows) use `.fixedHeight`: every card needs
    /// to look the same regardless of each source's real aspect ratio
    /// (a tall Keychain Access window next to a wide YouTube tab), so the
    /// box itself is a constant size. The area picker's preview uses
    /// `.aspectFit` instead, because its crop-box overlay is positioned by
    /// scaling the *display's own* proportions — the preview has to show
    /// the whole display at its own aspect ratio for that math to be
    /// right, so there it's the box, not just the image, that adapts.
    enum SizingMode {
        case fixedHeight(CGFloat)
        case aspectFit(CGFloat)
    }

    let source: Source
    var sizing: SizingMode = .fixedHeight(130)

    @State private var image: NSImage?

    private let loader = CaptureThumbnailLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.3))

            if let image {
                // .fit, not .fill: the whole image stays visible, scaled to
                // the box by whichever dimension is tighter (in practice
                // almost always width, since windows tend to be wider than
                // this box is tall) — never cropped. Whatever's left over
                // shows the placeholder fill behind it rather than cropping
                // in to erase it, and since the box itself is still the
                // same fixed size for every card either way, cards stay
                // uniform regardless of each source's own aspect ratio.
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .modifier(SizingModifier(sizing: sizing))
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

    private struct SizingModifier: ViewModifier {
        let sizing: SizingMode

        func body(content: Content) -> some View {
            switch sizing {
            case .fixedHeight(let height):
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            case .aspectFit(let ratio):
                content
                    .aspectRatio(ratio, contentMode: .fit)
            }
        }
    }
}
