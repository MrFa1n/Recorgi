import SwiftUI
import AppKit

/// `.navigationTitle("")` doesn't actually clear the window's title bar
/// text on macOS — an empty title falls back to the app's own bundle name
/// ("Recorgi"), which is exactly what was already showing, so it's
/// visually indistinguishable from not setting it at all. The only way to
/// genuinely suppress the title text while keeping the rest of the title
/// bar (traffic lights, the sidebar-toggle toolbar button) is the AppKit-
/// level NSWindow.titleVisibility, which SwiftUI has no modifier for —
/// hence grabbing the window via a zero-size NSViewRepresentable.
struct WindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            view.window?.titleVisibility = .hidden
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
