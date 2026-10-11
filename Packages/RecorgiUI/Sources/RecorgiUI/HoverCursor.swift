import SwiftUI
import AppKit

/// Native AppKit buttons don't switch the cursor to a pointing hand on
/// hover the way web buttons do — applied to Recorgi's interactive
/// controls for a clearer "this is clickable" affordance.
extension View {
    func hoverCursor(_ cursor: NSCursor = .pointingHand) -> some View {
        onHover { isHovering in
            if isHovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
