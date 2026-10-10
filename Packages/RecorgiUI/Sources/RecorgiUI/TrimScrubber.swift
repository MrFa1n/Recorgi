import SwiftUI

/// Draggable-handle trim bar: the highlighted range between the two handles
/// is what gets exported; the thin vertical line is the live playhead.
/// Tapping the track (not a handle) seeks playback there.
struct TrimScrubber: View {
    let duration: Double
    @Binding var trimStart: Double
    @Binding var trimEnd: Double
    let playhead: Double
    let onSeek: (Double) -> Void

    private let handleWidth: CGFloat = 12
    private let trackHeight: CGFloat = 36
    private let minimumGap: Double = 0.25

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let startX = x(for: trimStart, width: width)
            let endX = x(for: trimEnd, width: width)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: trackHeight)

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: max(0, endX - startX), height: trackHeight)
                    .offset(x: startX)

                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2, height: trackHeight + 8)
                    .offset(x: x(for: playhead, width: width) - 1)

                handle
                    .offset(x: startX - handleWidth / 2)
                    .gesture(dragGesture(width: width, movingStart: true))

                handle
                    .offset(x: endX - handleWidth / 2)
                    .gesture(dragGesture(width: width, movingStart: false))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let fraction = min(max(0, value.location.x / width), 1)
                        onSeek(fraction * duration)
                    }
            )
        }
        .frame(height: trackHeight + 8)
    }

    private var handle: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: handleWidth, height: trackHeight + 8)
    }

    private func x(for time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    private func dragGesture(width: CGFloat, movingStart: Bool) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let fraction = min(max(0, value.location.x / width), 1)
                let time = fraction * duration
                if movingStart {
                    trimStart = max(0, min(time, trimEnd - minimumGap))
                } else {
                    trimEnd = min(duration, max(time, trimStart + minimumGap))
                }
            }
    }
}
