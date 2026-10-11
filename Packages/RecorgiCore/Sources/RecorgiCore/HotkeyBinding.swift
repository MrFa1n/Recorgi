/// Modifier keys for a hotkey binding. A separate, framework-free bit set
/// rather than reusing AppKit's NSEvent.ModifierFlags, so this type stays
/// usable from RecorgiCore — converted to Carbon's modifier bits in
/// RecorgiCapture (HotkeyBinding+Carbon.swift) and to NSEvent.ModifierFlags
/// in RecorgiUI, same split as AccentColorChoice's NSColor/Color conversions.
public struct HotkeyModifiers: OptionSet, Codable, Sendable, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command = HotkeyModifiers(rawValue: 1 << 0)
    public static let option = HotkeyModifiers(rawValue: 1 << 1)
    public static let control = HotkeyModifiers(rawValue: 1 << 2)
    public static let shift = HotkeyModifiers(rawValue: 1 << 3)
}

/// A single key combination bound to a global hotkey action. `keyCode` is a
/// virtual (position-based) key code — the same thing Carbon's
/// RegisterEventHotKey takes — so it stays correct regardless of keyboard
/// layout; `displayLabel` is a human-readable string ("⌘⇧R") captured once
/// at record time purely for display, not re-derived from keyCode later.
public struct HotkeyBinding: Equatable, Codable, Sendable {
    public var keyCode: UInt32
    public var modifiers: HotkeyModifiers
    public var displayLabel: String

    public init(keyCode: UInt32, modifiers: HotkeyModifiers, displayLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayLabel = displayLabel
    }
}
