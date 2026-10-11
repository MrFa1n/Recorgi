import SwiftUI
import AppKit

/// Drop-in replacement for the plain-style rename `TextField`, needed only
/// because SwiftUI has no API for a `TextField`'s text-selection highlight
/// on macOS — that color lives on the AppKit field editor (a shared
/// `NSTextView`), which only an `NSViewRepresentable` gets direct access
/// to. `.tint()` does not reach it.
///
/// The selection background is the accent color blended toward white
/// (matching how the system derives its own selection color from the
/// accent color — a visibly lighter shade, not the same color translucent),
/// while the insertion-point caret stays the full accent color.
struct ThemedRenameField: NSViewRepresentable {
    @Binding var text: String
    let tint: NSColor
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.usesSingleLineMode = true
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        applySelectionColors(tint, to: nsView.currentEditor() as? NSTextView)
    }

    private func applySelectionColors(_ tint: NSColor, to editor: NSTextView?) {
        guard let editor else { return }
        editor.selectedTextAttributes = [
            .backgroundColor: tint.blended(withFraction: 0.55, of: .white) ?? tint,
            .foregroundColor: NSColor.labelColor
        ]
        editor.insertionPointColor = tint
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ThemedRenameField
        init(_ parent: ThemedRenameField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.applySelectionColors(parent.tint, to: field.currentEditor() as? NSTextView)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}
