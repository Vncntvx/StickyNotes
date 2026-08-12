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
        #expect(NoteWindowDerivations.toolbarVisibilityPriority(
                    itemIdentifier: NoteToolbarSpec.pinIdentifier) == .high)
    }

    @Test
    func insertUsesHighVisibilityPriority() {
        // 004 T065 (2026-08-13): the narrow-state design keeps Insert
        // visible next to Pin — the system overflow carries Appearance and
        // More instead (no "…" item trapped inside "»").
        #expect(NoteWindowDerivations.toolbarVisibilityPriority(
                    itemIdentifier: NoteToolbarSpec.insertIdentifier) == .high)
    }

    @Test
    func appearanceAndMoreUseStandardPriority() {
        #expect(NoteWindowDerivations.toolbarVisibilityPriority(
                    itemIdentifier: NoteToolbarSpec.appearanceIdentifier) == .standard)
        #expect(NoteWindowDerivations.toolbarVisibilityPriority(
                    itemIdentifier: NoteToolbarSpec.moreIdentifier) == .standard)
    }

    @Test
    func highIsBelowUserLevel() {
        // R7 fallback: `.high` > `.standard` and < `.user` — the pinned
        // recommendation band for always-visible items (NSToolbarItem.h).
        let high = NoteWindowDerivations.toolbarVisibilityPriority(
            itemIdentifier: NoteToolbarSpec.pinIdentifier).rawValue
        let standard = NoteWindowDerivations.toolbarVisibilityPriority(
            itemIdentifier: NoteToolbarSpec.moreIdentifier).rawValue
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
        // 004 T067 (2026-08-13): the 2+2 `.space` grouping was reverted —
        // four buttons are too few for two glass islands. This single
        // four-item strip (no separator) IS the layout.
    }

    @Test
    func toolbarButtonsUseBorderlessBezelAndTightSymbols() {
        // 004 T067 (2026-08-13 user feedback): one glass container, four
        // borderless items — at rest the buttons have NO capsule
        // boundaries (hover/press/keyboard shows the system response);
        // Liquid Glass stays as the overall surface, not per-item pills.
        // More uses the light `ellipsis` glyph; the palette is optically
        // 1pt smaller than the other symbols.
        #expect(NoteToolbarSpec.buttonBezelStyle == .toolbar,
                "resting buttons must be borderless (.toolbar bezel)")
        #expect(NoteToolbarSpec.moreSymbolName == "ellipsis",
                "More uses the light ellipsis glyph (not ellipsis.circle)")
        #expect(NoteToolbarSpec.symbolPointSize == 14,
                "tight symbol size (was visually too wide per-item)")
        #expect(NoteToolbarSpec.paletteSymbolPointSize == NoteToolbarSpec.symbolPointSize - 1,
                "palette optically 1pt smaller than the other symbols")
    }

    @Test
    func toolbarUsesSmallSizeModeForMediumDensity() {
        // 004 T064 (2026-08-13 user feedback): the glass toolbar read as a
        // heavy segmented control — four large capsules inside a large
        // capsule. Reduce to AppKit's medium density band: small size mode
        // + small control size (height ~10–15% less, per-item horizontal
        // padding ~15–20% less; glass bezel and hover/press morphing stay
        // system-provided).
        #expect(NoteToolbarSpec.toolbarSizeMode == .small,
                "toolbar size mode must be .small (medium density)")
        #expect(NoteToolbarSpec.buttonControlSize == .small,
                "toolbar buttons must use .small control size")
    }
}
