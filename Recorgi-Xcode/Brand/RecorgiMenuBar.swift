import AppKit

/// Состояние записи и соответствующий ему значок в строке меню.
enum RecordingState {
    case idle, recording, paused

    /// Имя набора картинок в Assets.xcassets.
    var menuBarImageName: String {
        switch self {
        case .idle: "MenuBarIdle"
        case .recording: "MenuBarRecording"
        case .paused: "MenuBarPaused"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle: "Recorgi: запись не идёт"
        case .recording: "Recorgi: идёт запись"
        case .paused: "Recorgi: запись на паузе"
        }
    }
}

/// Значок Recorgi в строке меню.
/// «Ожидание» и «Пауза» — шаблонные картинки, система сама красит их под строку меню.
/// «Запись» — цветная (красная точка), поэтому шаблонный режим для неё выключен,
/// а светлый и тёмный варианты лежат в каталоге ассетов.
final class RecorgiStatusItem {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(menu: NSMenu) {
        item.menu = menu
        update(.idle)
    }

    func update(_ state: RecordingState) {
        guard let button = item.button else { return }
        let image = NSImage(named: state.menuBarImageName)
        image?.isTemplate = state != .recording
        button.image = image
        button.setAccessibilityLabel(state.accessibilityLabel)
    }
}
