import SwiftUI

enum SidebarSection: String, Identifiable, CaseIterable, Hashable {
    case record
    case recordings
    case captureRegion
    case audioSources
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .record: "Запись"
        case .recordings: "Записи"
        case .captureRegion: "Область записи"
        case .audioSources: "Источники звука"
        case .general: "Основные"
        }
    }

    var systemImage: String {
        switch self {
        case .record: "record.circle.fill"
        case .recordings: "film.stack.fill"
        case .captureRegion: "viewfinder.rectangular"
        case .audioSources: "waveform"
        case .general: "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .record: .red
        case .recordings: .orange
        case .captureRegion: .teal
        case .audioSources: .blue
        case .general: .gray
        }
    }
}
