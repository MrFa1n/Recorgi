import SwiftUI
import RecorgiCapture

/// A per-track mini timeline for one audio track's volume: an overall gain
/// slider plus any number of region overrides — "boost this part, lower
/// that part" — added by dragging on empty space, resized by their edges,
/// moved by their middle, same drag-handle interaction style as
/// TrimScrubber. Tapping a region selects it and reveals its own gain
/// slider and a delete button.
struct VolumeRegionTimeline: View {
    let duration: Double
    let trackLabel: String
    let trackColor: Color
    @Binding var baseGain: Double
    @Binding var regions: [AudioVolumeRegion]

    @State private var selectedRegionID: UUID?
    @State private var dragState: DragState?

    private let trackHeight: CGFloat = 28
    private let edgeHandleWidth: CGFloat = 10
    private let minimumRegionDuration: Double = 0.3

    private enum DragState {
        case creating(startSeconds: Double, currentSeconds: Double)
        case resizingStart(regionID: UUID, original: AudioVolumeRegion)
        case resizingEnd(regionID: UUID, original: AudioVolumeRegion)
        case moving(regionID: UUID, original: AudioVolumeRegion, grabSeconds: Double)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(trackLabel)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int((baseGain * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    baseGain = 1.0
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Сбросить общую громкость до 100%")
                .disabled(baseGain == 1.0)
                .hoverCursor()
            }
            Slider(value: $baseGain, in: 0...2, step: 0.01)
                .labelsHidden()
                .tint(trackColor)

            timeline

            if let selectedRegionID, let index = regions.firstIndex(where: { $0.id == selectedRegionID }) {
                regionEditor(index: index)
            } else {
                Text("Перетащи по пустому месту на полосе, чтобы выделить участок и усилить или приглушить только его")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timeline: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: trackHeight)

                ForEach(regions) { region in
                    regionBlock(region, width: width, isSelected: region.id == selectedRegionID)
                        .onTapGesture { selectedRegionID = region.id }
                }

                if case .creating(let start, let current) = dragState {
                    let lo = min(start, current)
                    let hi = max(start, current)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(trackColor.opacity(0.4))
                        .frame(width: max(0, x(hi, width) - x(lo, width)), height: trackHeight)
                        .offset(x: x(lo, width))
                }
            }
            .frame(height: trackHeight)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: trackHeight)
    }

    private func regionBlock(_ region: AudioVolumeRegion, width: CGFloat, isSelected: Bool) -> some View {
        let startX = x(region.startSeconds, width)
        let endX = x(region.endSeconds, width)
        let color = region.gain >= 1.0 ? trackColor : .orange

        return RoundedRectangle(cornerRadius: 4)
            .fill(color.opacity(isSelected ? 0.55 : 0.3))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: isSelected ? 2 : 0))
            .frame(width: max(2, endX - startX), height: trackHeight)
            .offset(x: startX)
    }

    private func regionEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(formatted(regions[index].startSeconds)) – \(formatted(regions[index].endSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((regions[index].gain * 100).rounded()))%")
                    .font(.caption)
                    .monospacedDigit()
                Button(role: .destructive) {
                    let id = regions[index].id
                    regions.removeAll { $0.id == id }
                    selectedRegionID = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .hoverCursor()
            }
            Slider(
                value: Binding(get: { regions[index].gain }, set: { regions[index].gain = $0 }),
                in: 0...2,
                step: 0.01
            )
            .labelsHidden()
            .tint(regions[index].gain >= 1.0 ? trackColor : .orange)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let startSeconds = seconds(for: value.startLocation.x, width: width)
                let currentSeconds = seconds(for: value.location.x, width: width)

                if dragState == nil {
                    dragState = initialDragState(at: value.startLocation.x, width: width, startSeconds: startSeconds)
                }

                switch dragState {
                case .creating:
                    dragState = .creating(startSeconds: startSeconds, currentSeconds: currentSeconds)

                case .resizingStart(let id, let original):
                    if let idx = regions.firstIndex(where: { $0.id == id }) {
                        regions[idx].startSeconds = min(max(0, currentSeconds), original.endSeconds - minimumRegionDuration)
                    }

                case .resizingEnd(let id, let original):
                    if let idx = regions.firstIndex(where: { $0.id == id }) {
                        regions[idx].endSeconds = max(min(duration, currentSeconds), original.startSeconds + minimumRegionDuration)
                    }

                case .moving(let id, let original, let grabSeconds):
                    if let idx = regions.firstIndex(where: { $0.id == id }) {
                        let span = original.endSeconds - original.startSeconds
                        let delta = currentSeconds - grabSeconds
                        let newStart = min(max(0, original.startSeconds + delta), duration - span)
                        regions[idx].startSeconds = newStart
                        regions[idx].endSeconds = newStart + span
                    }

                case nil:
                    break
                }
            }
            .onEnded { _ in
                defer { dragState = nil }
                switch dragState {
                case .creating(let start, let current):
                    let lo = min(start, current)
                    let hi = max(start, current)
                    guard hi - lo >= minimumRegionDuration else { return }
                    let region = AudioVolumeRegion(startSeconds: lo, endSeconds: hi, gain: 1.5)
                    regions.append(region)
                    selectedRegionID = region.id
                case .resizingStart(let id, _), .resizingEnd(let id, _), .moving(let id, _, _):
                    selectedRegionID = id
                case nil:
                    break
                }
            }
    }

    private func initialDragState(at startX: CGFloat, width: CGFloat, startSeconds: Double) -> DragState {
        for region in regions {
            let regionStartX = x(region.startSeconds, width)
            let regionEndX = x(region.endSeconds, width)
            if abs(startX - regionStartX) <= edgeHandleWidth {
                return .resizingStart(regionID: region.id, original: region)
            }
            if abs(startX - regionEndX) <= edgeHandleWidth {
                return .resizingEnd(regionID: region.id, original: region)
            }
            if startX > regionStartX && startX < regionEndX {
                return .moving(regionID: region.id, original: region, grabSeconds: startSeconds)
            }
        }
        return .creating(startSeconds: startSeconds, currentSeconds: startSeconds)
    }

    private func x(_ seconds: Double, _ width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(seconds / duration) * width
    }

    private func seconds(for x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(0, x / width), 1) * duration
    }

    private func formatted(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
