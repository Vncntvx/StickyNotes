import Testing
import Foundation
import SwiftUI
@testable import StickyNotes

// MARK: - Menu checklist tests (003 T006, SC-017/FR-072)
//
// Per tasks.md T006: every IMPORTANT toolbar command must also exist as a
// menu-bar command (File/Edit/View/Window/Help) so nothing is lost when the
// library footer and toolbar chrome are reduced (SC-017). The app builds
// its CommandGroups from `MenuCommandCatalog`, so the catalog IS the menu
// source of truth — this test asserts the catalog covers the required
// checklist.

@Suite struct MenuChecklistTests {

    @Test
    func newNoteHasMenuCommand() {
        #expect(MenuCommandCatalog.command(located: .file, withShortcut: "n", modifiers: .command) != nil,
                "File > New Note (⌘N) must exist")
    }

    @Test
    func searchFocusHasMenuCommand() {
        #expect(MenuCommandCatalog.command(located: .view, withShortcut: "f", modifiers: .command) != nil,
                "View > Search (⌘F) must focus the library search")
    }

    @Test
    func sortHasMenuCommand() {
        // Sort switcher: reachable via a View menu submenu (SC-017).
        #expect(MenuCommandCatalog.commands(located: .view).contains { $0.title == "Sort" },
                "View menu must contain a Sort submenu")
    }

    @Test
    func notesTrashDestinationHasMenuCommand() {
        // The Notes/Trash destination control needs a menu counterpart.
        #expect(MenuCommandCatalog.commands(located: .view).contains { $0.title == "Trash" }
                || MenuCommandCatalog.commands(located: .file).contains { $0.title == "Trash" },
                "Notes/Trash destination must be reachable from the menu bar")
    }

    @Test
    func moveToTrashHasMenuCommand() {
        #expect(MenuCommandCatalog.command(located: .file, withShortcut: "\u{8}", modifiers: .command) != nil,
                "File > Move to Trash (⌘⌫) must exist")
    }

    @Test
    func permanentDeleteHasMenuCommand() {
        #expect(MenuCommandCatalog.commands(located: .file).contains { $0.title.contains("Delete") },
                "File menu must contain a permanent-delete command")
    }

    @Test
    func settingsHasMenuCommand() {
        #expect(MenuCommandCatalog.commands(located: .file).contains { $0.title == "Settings…" },
                "Settings must be reachable via the menu bar")
    }

    @Test
    func helpAndAboutHaveMenuCommands() {
        #expect(MenuCommandCatalog.commands(located: .help).contains { $0.title == "Help" },
                "Help menu must contain Help")
        #expect(MenuCommandCatalog.commands(located: .app).contains { $0.title == "About Sticky Notes" },
                "App menu must contain About")
    }

    @Test
    func importantToolbarCommandsCovered() {
        // The SC-017 checklist as a whole: the toolbar's important commands
        // (new note, search focus, sort, destination, move-to-Trash,
        // permanent delete, settings, help, about) must ALL be in the menu
        // catalog.
        let all = MenuCommandCatalog.all
        let titles = all.map(\.title)
        for required in ["New Note", "Sort", "Trash", "Move to Trash", "Settings…", "Help", "About Sticky Notes"] {
            #expect(titles.contains(required), "menu catalog must contain '\(required)' (SC-017)")
        }
    }

    // MARK: - 003 T188 (FR-072 Rev 3, 2026-08-14): restore/empty-trash/sync

    @Test
    func restoreHasMenuCommand() {
        #expect(MenuCommandCatalog.commands(located: .file).contains { $0.title == "Restore" },
                "File > Restore must exist (FR-072 Rev 3)")
    }

    @Test
    func emptyTrashHasMenuCommand() {
        #expect(MenuCommandCatalog.commands(located: .file).contains { $0.title == "Empty Trash…" },
                "File > Empty Trash… must exist (FR-072 Rev 3)")
    }

    @Test
    func syncNowHasMenuCommand() {
        #expect(MenuCommandCatalog.commands(located: .file).contains { $0.title == "Sync Now" },
                "File > Sync Now must exist (FR-072 Rev 3)")
    }

    // MARK: - 004 T047 (FR-011/FR-029, 003 FR-072 semantics)

    @Test
    func alwaysOnTopHasMenuCommand() {
        // 004 T021: the pin must exist as a View menu command (toggle on
        // the key note window — the toolbar is not the only path).
        #expect(MenuCommandCatalog.commands(located: .view).contains { $0.title == "Always on Top" },
                "View > Always on Top must exist (004 T021/FR-029)")
    }

    @Test
    func insertImageHasMenuCommand() {
        // 004 T035: the unified image insertion path in the menu.
        #expect(MenuCommandCatalog.commands(located: .edit).contains { $0.title == "Insert Image…" },
                "Edit/Insert > Insert Image… must exist (004 T035/FR-010)")
    }

    @Test
    func formatCommandsHaveMenuEntries() {
        // 004 T040: the Format group (B/I/U/strikethrough/code/size) — the
        // stable formatting entry point (FR-011/FR-012).
        let editTitles = Set(MenuCommandCatalog.commands(located: .edit).map(\.title))
        for required in ["Bold", "Italic", "Underline", "Strikethrough", "Code Style", "Text Size"] {
            #expect(editTitles.contains(required), "Format command '\(required)' must be in the catalog (004 T040)")
        }
        #expect(MenuCommandCatalog.command(located: .edit, withShortcut: "b", modifiers: .command)?.title == "Bold")
        #expect(MenuCommandCatalog.command(located: .edit, withShortcut: "i", modifiers: .command)?.title == "Italic")
        #expect(MenuCommandCatalog.command(located: .edit, withShortcut: "u", modifiers: .command)?.title == "Underline")
    }
}
