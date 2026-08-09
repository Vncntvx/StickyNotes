import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - Appearance-panel state tests (004 T009, spec FR-008/FR-009)
//
// Per tasks.md T009: opacity clamping (0.40–1.00, 0.05 steps), the "NN%"
// full-value format (never "10…"), and reset-to-default semantics
// (default palette color + transparency 1.0).

@Suite struct AppearancePanelStateTests {

    private let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000022")!

    // MARK: Opacity percent formatting (FR-009)

    @Test
    func opacityFormatsAsCompletePercent() {
        #expect(NoteWindowDerivations.formatOpacityPercent(0.40) == "40%")
        #expect(NoteWindowDerivations.formatOpacityPercent(0.60) == "60%")
        #expect(NoteWindowDerivations.formatOpacityPercent(1.00) == "100%")
    }

    @Test
    func opacityFormatNeverTruncatesHundred() {
        // FR-009 regression: "100%" must never render as "10…".
        #expect(NoteWindowDerivations.formatOpacityPercent(1.00) == "100%", "full value, never truncated")
    }

    @Test
    func opacityFormatRoundsToNearestPercent() {
        #expect(NoteWindowDerivations.formatOpacityPercent(0.65) == "65%")
        #expect(NoteWindowDerivations.formatOpacityPercent(0.4) == "40%")
    }

    // MARK: Clamping (001 FR-041a semantics)

    @Test
    func opacityClampsToBounds() {
        #expect(NoteWindowDerivations.clampedOpacity(0.20) == 0.40, "clamps below the floor")
        #expect(NoteWindowDerivations.clampedOpacity(1.30) == 1.00, "clamps above the ceiling")
        #expect(NoteWindowDerivations.clampedOpacity(0.60) == 0.60, "steps stay exactly equal to their Double literal")
        #expect(NoteWindowDerivations.clampedOpacity(0.40) == 0.40)
        #expect(NoteWindowDerivations.clampedOpacity(1.00) == 1.00)
    }

    @Test
    func opacitySnapsToNearestStep() {
        // 0.05-step quantization (FR-041a).
        #expect(NoteWindowDerivations.clampedOpacity(0.625) == 0.65)
        #expect(NoteWindowDerivations.clampedOpacity(0.626) == 0.65)
    }

    @Test
    func opacityStepsAreThirteen() {
        #expect(NoteAppearance.OpacityBounds.allSteps.count == 13)
        #expect(NoteAppearance.OpacityBounds.allSteps.first == 0.40)
        #expect(NoteAppearance.OpacityBounds.allSteps.last == 1.00)
    }

    // MARK: Reset-to-default (FR-008)

    @Test
    func resetRestoresDefaultPaletteAndFullOpacity() {
        var note = Note(
            colorKey: .custom,
            customColor: "#A1B2C3",
            transparency: 0.55,
            lastModifiedDeviceId: deviceId
        )
        note = NoteWindowDerivations.resetAppearance(of: note)
        #expect(note.colorKey == .yellow, "default palette color restored")
        #expect(note.customColor == nil, "custom color cleared")
        #expect(note.transparency == 1.0, "full opacity restored")
    }

    @Test
    func paletteStorageMappingPreservesPeachAsCustom() {
        // 001 FR-032: peach has no Domain built-in; it is preserved as a
        // custom color with the palette's designed light value.
        let note = Note(lastModifiedDeviceId: deviceId)
        let peach = NoteWindowDerivations.note(applyingPaletteKey: .peach, to: note)
        #expect(peach.colorKey == .custom)
        #expect(peach.customColor == "#FFC9A8")
        #expect(NoteWindowDerivations.paletteKey(for: peach) == nil, "custom colors never enter the palette")
    }

    @Test
    func paletteStorageMappingKeepsBuiltinKeysVerbatim() {
        let note = Note(lastModifiedDeviceId: deviceId)
        let lavender = NoteWindowDerivations.note(applyingPaletteKey: .lavender, to: note)
        #expect(lavender.colorKey == .purple, "紫→薰衣草 maps to the stored purple key (FR-032)")
        #expect(lavender.customColor == nil)
        #expect(NoteWindowDerivations.paletteKey(for: lavender) == .lavender)
    }
}
