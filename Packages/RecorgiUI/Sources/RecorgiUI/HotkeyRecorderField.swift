import SwiftUI
import AppKit
import RecorgiCore

/// A button that captures the next key combination the user presses (while
/// this app is focused — which is all that's needed here, since the
/// resulting binding then gets registered as a true system-wide hotkey
/// separately, by GlobalHotkeyManager in RecorgiCapture) and writes it into
/// `binding`. Requires at least one modifier key: a bare, unmodified key
/// (just "R", say) becoming a *global* hotkey would hijack normal typing
/// everywhere else in the system, not just inside this app.
struct HotkeyRecorderField: View {
    @Binding var binding: HotkeyBinding?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Нажмите клавиши…" : (binding?.displayLabel ?? "Не задано"))
                    .frame(minWidth: 130)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .hoverCursor()

            if binding != nil {
                Button {
                    binding = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .hoverCursor()
                .help("Очистить")
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
                NSSound.beep()
                return nil
            }
            var modifiers: HotkeyModifiers = []
            if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
            if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
            if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
            if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
            binding = HotkeyBinding(
                keyCode: UInt32(event.keyCode),
                modifiers: modifiers,
                displayLabel: Self.displayLabel(modifierFlags: event.modifierFlags, keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
            )
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func displayLabel(modifierFlags: NSEvent.ModifierFlags, keyCode: UInt16, characters: String?) -> String {
        var parts: [String] = []
        if modifierFlags.contains(.control) { parts.append("⌃") }
        if modifierFlags.contains(.option) { parts.append("⌥") }
        if modifierFlags.contains(.shift) { parts.append("⇧") }
        if modifierFlags.contains(.command) { parts.append("⌘") }
        parts.append(keyLabel(keyCode: keyCode, characters: characters))
        return parts.joined()
    }

    // Virtual key codes for the keys without a sensible `characters`
    // representation (arrows, function keys, space, etc.) — fixed,
    // position-based codes, independent of keyboard layout.
    private static func keyLabel(keyCode: UInt16, characters: String?) -> String {
        switch Int(keyCode) {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Esc"
        case 51: return "Delete"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            if let characters, !characters.isEmpty {
                return characters.uppercased()
            }
            return "Key \(keyCode)"
        }
    }
}
