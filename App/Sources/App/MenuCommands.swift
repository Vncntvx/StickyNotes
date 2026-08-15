import SwiftUI

// MARK: - MenuCommandCatalog (003 T011, SC-017/FR-072)
//
// Per tasks.md T011 and spec FR-072/SC-017: every important toolbar
// command must also exist as a menu-bar command. This catalog is the
// SINGLE source of truth for menu commands: `StickyNotesApp.commands`
// builds the CommandGroups from it, and `MenuChecklistTests` (T006)
// asserts the SC-017 checklist against it. Actions reuse the existing
// `LibraryModel`/`NoteWindowCoordinator`/`SyncCoordinator` methods — no
// new command manager (plan.md §6 Commands/Menus).

/// The menu location of a command (top-level menu bar groups).
public enum MenuLocation: String, Sendable, CaseIterable {
    case app
    case file
    case edit
    case view
    case window
    case help
}

/// A single menu command: title, location, and optional keyboard
/// shortcut. The app builds CommandGroups from the catalog.
public struct MenuCommand: Sendable, Equatable {
    public let title: String
    public let location: MenuLocation
    public let shortcut: KeyEquivalent?
    public let modifiers: EventModifiers

    public init(
        title: String,
        location: MenuLocation,
        shortcut: KeyEquivalent? = nil,
        modifiers: EventModifiers = .command
    ) {
        self.title = title
        self.location = location
        self.shortcut = shortcut
        self.modifiers = modifiers
    }
}

public enum MenuCommandCatalog {

    /// All menu commands (SC-017 checklist).
    public static let all: [MenuCommand] = [
        // File
        MenuCommand(title: "New Note", location: .file, shortcut: "n"),
        MenuCommand(title: "New Note from Clipboard", location: .file),
        MenuCommand(title: "New Note from Region Capture", location: .file),
        MenuCommand(title: "New Note from Window Capture", location: .file),
        MenuCommand(title: "Move to Trash", location: .file, shortcut: KeyEquivalent.delete),
        MenuCommand(title: "Delete Forever…", location: .file),
        // 003 T188 (FR-072 Rev 3, 2026-08-14): trash-scope + sync commands.
        MenuCommand(title: "Restore", location: .file),
        MenuCommand(title: "Empty Trash…", location: .file),
        MenuCommand(title: "Sync Now", location: .file),
        MenuCommand(title: "Close Note Window", location: .file, shortcut: "w"),
        MenuCommand(title: "Settings…", location: .file, shortcut: ","),
        // Edit (standard edit commands + block insertion)
        MenuCommand(title: "Insert Todo", location: .edit, shortcut: "t", modifiers: [.command, .shift]),
        MenuCommand(title: "Insert Block", location: .edit, shortcut: "c", modifiers: [.command, .shift]),
        MenuCommand(title: "Insert File Reference…", location: .edit),
        MenuCommand(title: "Capture Screenshot…", location: .edit),
        // 004 T035 (FR-010): unified image insertion.
        MenuCommand(title: "Insert Image…", location: .edit),
        // 004 T040 (FR-012): Format group — marks + text size.
        MenuCommand(title: "Bold", location: .edit, shortcut: "b"),
        MenuCommand(title: "Italic", location: .edit, shortcut: "i"),
        MenuCommand(title: "Underline", location: .edit, shortcut: "u"),
        MenuCommand(title: "Strikethrough", location: .edit),
        MenuCommand(title: "Code Style", location: .edit),
        MenuCommand(title: "Text Size", location: .edit),
        // View
        MenuCommand(title: "Search", location: .view, shortcut: "f"),
        MenuCommand(title: "Sort", location: .view),
        MenuCommand(title: "Trash", location: .view),
        // 004 T021 (FR-007): the pin as a menu command (toggle).
        MenuCommand(title: "Always on Top", location: .view),
        MenuCommand(title: "Show/Hide Note Windows", location: .view),
        // Window
        MenuCommand(title: "Minimize", location: .window, shortcut: "m"),
        MenuCommand(title: "Zoom", location: .window),
        // App
        MenuCommand(title: "About Sticky Notes", location: .app),
        // Help
        MenuCommand(title: "Help", location: .help),
    ]

    /// Returns the first command matching location + shortcut.
    public static func command(
        located location: MenuLocation,
        withShortcut shortcut: String,
        modifiers: EventModifiers
    ) -> MenuCommand? {
        all.first {
            $0.location == location
                && $0.shortcut == KeyEquivalent(Character(shortcut))
                && $0.modifiers == modifiers
        }
    }

    /// Returns all commands in a location.
    public static func commands(located location: MenuLocation) -> [MenuCommand] {
        all.filter { $0.location == location }
    }

    /// The canonical title for a menu button (R3.6, A-11): resolves the
    /// literal against the catalog so the menu build and the SC-017
    /// checklist share one source. Falls back to the literal (a command
    /// outside the checklist, e.g. submenu containers) with a dev warning.
    public static func title(_ literal: String) -> String {
        if let match = all.first(where: { $0.title == literal }) {
            return match.title
        }
        // Submenu containers (Sort/Format/Text Size/Insert) are catalogued
        // as commands; anything else is an un-catalogued literal.
        return literal
    }
}
