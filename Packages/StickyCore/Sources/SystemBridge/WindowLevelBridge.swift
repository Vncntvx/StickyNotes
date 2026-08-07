import Foundation
import AppKit
import Domain

// MARK: - WindowLevelBridge (T165)
//
// Per tasks.md T165 and spec FR-036: per-window floating level via AppKit
// (`NSWindow.level`). AppKit isolated here. Pure mapping + a thin
// main-actor application helper; the mapping is testable without windows.

/// The window-level bridge: maps note state to AppKit window levels and
/// applies them (FR-036 Always-on-Top).
public enum WindowLevelBridge {

    /// The AppKit level for a note window.
    public static func level(alwaysOnTop: Bool) -> NSWindow.Level {
        alwaysOnTop ? .floating : .normal
    }

    /// Applies the level for the note's Always-on-Top state on the main
    /// actor.
    @MainActor
    public static func apply(_ window: NSWindow, alwaysOnTop: Bool) {
        window.level = level(alwaysOnTop: alwaysOnTop)
    }
}
