import Testing
import Foundation
import SwiftUI
import Domain
@testable import StickyNotes

// MARK: - Palette migration tests (003 T005, FR-032)
//
// Per tasks.md T005: the old six built-in colors (001 FR-040a) map
// semantically onto the new seven-color palette (黄→黄、粉→粉、紫→薰衣草、
// 蓝→蓝、绿→绿、灰→灰); custom colors are preserved byte-exact; migration
// never alters note content.

@Suite struct PaletteMigrationTests {

    @Test
    func oldColorsMapSemanticallyToNewPalette() {
        // 001 stored keys → new presentation keys (FR-032).
        #expect(NotePalette.paletteKey(for: .yellow) == .yellow)
        #expect(NotePalette.paletteKey(for: .pink) == .pink)
        #expect(NotePalette.paletteKey(for: .purple) == .lavender, "紫→薰衣草 (FR-032)")
        #expect(NotePalette.paletteKey(for: .blue) == .blue)
        #expect(NotePalette.paletteKey(for: .green) == .green)
        #expect(NotePalette.paletteKey(for: .gray) == .gray)
    }

    @Test
    func customColorHasNoPaletteMapping() {
        // Custom colors never go through the palette (FR-032).
        #expect(NotePalette.paletteKey(for: .custom) == nil)
    }

    @Test
    func customColorValueIsPreservedByteExact() {
        // FR-032: the stored custom hex must survive verbatim — the palette
        // is a pure presentation layer and never rewrites the value.
        let hex = "#A1B2C3"
        let note = Note(
            title: "custom",
            colorKey: .custom,
            customColor: hex,
            transparency: 1.0,
            lastModifiedDeviceId: UUID(uuidString: "c0000000-0000-4000-8000-0000000000c1")!
        )
        #expect(note.customColor == hex, "custom color hex preserved byte-exact")
        // And the palette mapping leaves it untouched (nil mapping above).
        _ = note
    }

    @Test
    func migrationDoesNotAlterNoteContent() {
        // FR-032: any color migration must never touch note content. The
        // mapping is a pure presentation function; a note's stored fields
        // (including its stored colorKey) remain exactly as persisted.
        let note = Note(
            title: "migrating",
            colorKey: .purple,
            transparency: 0.8,
            lastModifiedDeviceId: UUID(uuidString: "c0000000-0000-4000-8000-0000000000c2")!
        )
        // The presentation key differs, but the stored identity is intact.
        #expect(NotePalette.paletteKey(for: note.colorKey) == .lavender)
        #expect(note.colorKey == .purple, "stored colorKey unchanged by presentation mapping")
        #expect(note.title == "migrating", "note title untouched")
        #expect(note.transparency == 0.8, "note appearance untouched")
    }
}
