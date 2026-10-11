import os

/// Centralized `os.Logger` instances, one per functional area, all under
/// the app's own subsystem. Prefer these over `print()` everywhere there's
/// something worth being able to find later: unlike print, unified logging
/// is structured (filterable by subsystem/category/level), essentially
/// free when nobody's listening, and persisted by the system — so a
/// problem can be diagnosed after the fact via Console.app, `log show
/// --predicate 'subsystem == "com.recorgi.app"'`, or the in-app log export
/// in General settings, instead of only ever being visible live in Xcode.
///
/// Log liberally at the boundaries that actually matter for diagnosing a
/// problem: starting/stopping an operation, every error or unexpected
/// branch, every externally-triggered state change (permission results,
/// hotkey registration, device enumeration). Skip anything that fires on
/// every SwiftUI body re-evaluation or every frame — that's noise, not
/// signal, and would bury the entries that actually matter.
public enum Log {
    /// Matches `PRODUCT_BUNDLE_IDENTIFIER` in project.yml — also what the
    /// log export (and `log stream`/`log show` run by hand) filters on.
    public static let subsystem = "com.recorgi.app"

    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")
    public static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    public static let menuBar = Logger(subsystem: subsystem, category: "menuBar")
    public static let library = Logger(subsystem: subsystem, category: "library")
    public static let devices = Logger(subsystem: subsystem, category: "devices")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
