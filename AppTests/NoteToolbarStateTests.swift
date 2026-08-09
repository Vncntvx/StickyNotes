import Testing
import Foundation
import AppKit
@testable import StickyNotes

// MARK: - Toolbar-state tests (004 T010, spec FR-015a/FR-015c)
//
// Per tasks.md T010: `toolbarVisibilityPriority` (pin = .high, rest =
// .standard — FR-015a) and the fixed toolbar-item identifier set
// (FR-015c/Q3: product-fixed, no user customization).

@Suite struct NoteToolbarStateTests {

    @Test
    func pinUsesHighVisibilityPriority() {
        // FR-015a/Q2: the pin stays directly visible until the system can
        // no longer accommodate it (last into the overflow chevron).
        #expect(NoteWindowDerivations.toolbarVisibilityPriority(pin: true) == .high)
    }

    @Test
    func otherItemsUseStandardPriority() {
        #expect(NoteWindowDerivations.toolbarVisibilityPriority(pin: false) == .standard)
    }

    @Test
    func highIsBelowUserLevel() {
        // R7 fallback: `.high` > `.standard` and < `.user` — the pinned
        // recommendation band for always-visible items (NSToolbarItem.h).
        let high = NoteWindowDerivations.toolbarVisibilityPriority(pin: true).rawValue
        let standard = NoteWindowDerivations.toolbarVisibilityPriority(pin: false).rawValue
        let user = NSToolbarItem.VisibilityPriority.user.rawValue
        #expect(high > standard && high < user, "high sits in the always-visible band")
    }

    @Test
    func toolbarItemIdentifiersAreTheFixedSet() {
        // FR-015c/Q3: product-fixed — pin/appearance/insert/more, no user
        // customization, no extra items.
        #expect(NoteToolbarSpec.itemIdentifierStrings == [
            "note.toolbar.pin",
            "note.toolbar.appearance",
            "note.toolbar.insert",
            "note.toolbar.more",
        ])
    }
}
