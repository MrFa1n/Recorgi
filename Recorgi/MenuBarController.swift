import AppKit
import Combine
import RecorgiCore
import RecorgiCapture

/// Menu-bar status item: lets the user start/stop a recording and toggle
/// the two audio sources without bringing the main window forward, and
/// reopen the main window when it's been closed (AppDelegate keeps the app
/// running after that — see its own doc comment). `.task` instead of a
/// custom init with required parameters, same pattern as
/// GlobalHotkeyManager, since @StateObject properties can't reference
/// sibling @StateObject values during RecorgiApp's own initialization.
@MainActor
final class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var settings: RecordingSettings?
    private var engine: ScreenRecordingEngine?
    private var cancellables = Set<AnyCancellable>()

    /// Set from RecorgiApp via a tiny SwiftUI bridge view reading
    /// `@Environment(\.openWindow)` — the only supported way to recreate a
    /// WindowGroup's window on demand once it's been fully closed, not
    /// just ordered out.
    var openWindowAction: (() -> Void)?

    func start(settings: RecordingSettings, engine: ScreenRecordingEngine) {
        guard self.settings == nil else { return }
        self.settings = settings
        self.engine = engine

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        engine.$state
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
        updateIcon()
    }

    // Idle and paused are template images (baked into the asset catalog
    // itself via template-rendering-intent) so the system colors them to
    // match the menu bar automatically; recording is a real colored image
    // (red dot, separate light/dark variants in the catalog), so template
    // mode is explicitly off for it — matching the brand kit's own
    // RecorgiMenuBar.swift reference implementation (Recorgi-Xcode/Brand),
    // not copied verbatim here only because its RecordingState enum name
    // collides with RecorgiCore's.
    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let imageName: String
        let isTemplate: Bool
        let label: String
        switch engine?.state {
        case .recording:
            imageName = "MenuBarRecording"
            isTemplate = false
            label = "Recorgi — идёт запись"
        case .starting, .stopping:
            imageName = "MenuBarPaused"
            isTemplate = true
            label = "Recorgi — переключение"
        case .idle, nil:
            imageName = "MenuBarIdle"
            isTemplate = true
            label = "Recorgi"
        }
        let image = NSImage(named: imageName)
        image?.isTemplate = isTemplate
        button.image = image
        button.setAccessibilityLabel(label)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let settings, let engine else { return }

        let isRecording: Bool
        if case .recording = engine.state { isRecording = true } else { isRecording = false }

        let toggleItem = NSMenuItem(
            title: isRecording ? "Остановить запись" : "Начать запись",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let systemAudioItem = NSMenuItem(title: "Системный звук", action: #selector(toggleSystemAudio), keyEquivalent: "")
        systemAudioItem.target = self
        systemAudioItem.state = settings.isSystemAudioEnabled ? .on : .off
        menu.addItem(systemAudioItem)

        let microphoneItem = NSMenuItem(title: "Микрофон", action: #selector(toggleMicrophone), keyEquivalent: "")
        microphoneItem.target = self
        microphoneItem.state = settings.isMicrophoneEnabled ? .on : .off
        menu.addItem(microphoneItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Открыть Recorgi", action: #selector(showWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Выйти из Recorgi", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleRecording() {
        guard let settings, let engine else { return }
        Task {
            switch engine.state {
            case .idle:
                try? await engine.start(settings: settings)
            case .recording:
                await engine.stop()
            case .starting, .stopping:
                break
            }
        }
    }

    @objc private func toggleMicrophone() {
        settings?.isMicrophoneEnabled.toggle()
    }

    @objc private func toggleSystemAudio() {
        settings?.isSystemAudioEnabled.toggle()
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindowAction?()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}
