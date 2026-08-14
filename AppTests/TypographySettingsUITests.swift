import Testing
import Foundation
@testable import StickyNotes

// MARK: - Typography settings UI semantics (Phase 5, 2026-08-14)
//
// The Settings surface is a thin binding layer over the Phase 2 observable
// state (the persistence/commit semantics live in TypographyPreferencesTests).
// This suite pins the user-facing pieces that are unit-testable without UI
// automation: the three spacing presets have distinct localized display
// names (the segmented picker's labels), and the preset order is stable.

@MainActor
@Suite struct TypographySettingsUITests {

    @Test
    func spacingPresetDisplayNamesAreDistinct() {
        let names = TextSpacingPreset.allCases.map(\.displayName)
        #expect(Set(names).count == 3,
                "Compact / Default / Relaxed must have three distinct labels (got \(names))")
        #expect(names.allSatisfy { !$0.isEmpty }, "labels must resolve from the string catalog")
    }

    @Test
    func standardPresetIsTheDefaultDisplayMiddle() {
        // The picker presents the presets in declaration order with
        // standard (Default) in the middle — the zero-delta baseline.
        let cases = TextSpacingPreset.allCases
        #expect(cases == [.compact, .standard, .relaxed])
        // Localized (R3.8): assert language-independently — the middle
        // preset is the zero-delta standard and all three names differ.
        #expect(cases[1] == .standard, "the middle preset is the zero-delta baseline")
        #expect(Set(cases.map(\.displayName)).count == 3, "the three preset names must be distinct")
    }
}
