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
        #expect(NoteWindowDerivations.clampedOpacity(-0.20) == 0.0, "clamps below the floor")
        #expect(NoteWindowDerivations.clampedOpacity(1.30) == 1.00, "clamps above the ceiling")
        #expect(NoteWindowDerivations.clampedOpacity(0.60) == 0.60, "steps stay exactly equal to their Double literal")
        #expect(NoteWindowDerivations.clampedOpacity(0.0) == 0.0)
        #expect(NoteWindowDerivations.clampedOpacity(1.00) == 1.00)
    }

    @Test
    func opacitySnapsToNearestStep() {
        // 0.05-step quantization (FR-041a).
        #expect(NoteWindowDerivations.clampedOpacity(0.625) == 0.65)
        #expect(NoteWindowDerivations.clampedOpacity(0.626) == 0.65)
    }

    @Test
    func opacityStepsAreTwentyOne() {
        #expect(NoteAppearance.OpacityBounds.allSteps.count == 21)
        #expect(NoteAppearance.OpacityBounds.allSteps.first == 0.0)
        #expect(NoteAppearance.OpacityBounds.allSteps.last == 1.00)
    }

    @Test
    func opacityBoundsSpanZeroToHundred() {
        // 004 Q8 (2026-08-13 user directive): the slider range is 0%–100%,
        // NOT 40%–100% — the shared OpacityBounds constants are the single
        // source for the slider, the overflow menu steps, and the ⌥O
        // stepping path.
        #expect(NoteAppearance.OpacityBounds.minOpacity == 0.0, "floor is 0%")
        #expect(NoteAppearance.OpacityBounds.maxOpacity == 1.00, "ceiling is 100%")
        #expect(NoteAppearance.OpacityBounds.step == 0.05)
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

    // MARK: Live composition (004 T069, 2026-08-13 user report)

    @Test
    func appearanceCompositionCarriesLocalFieldsOverBaseNote() {
        // The panel must compose each change from the ORIGINAL base note +
        // the CURRENT local appearance state — never from a stale snapshot
        // (the slider used to read the snapshot value back, so the knob
        // never followed the mouse and the "NN%" label stayed frozen).
        var base = Note(lastModifiedDeviceId: deviceId)
        base.title = "keep me"
        base.alwaysOnTop = true
        let composed = NoteWindowDerivations.composeAppearance(
            base: base,
            colorKey: .blue,
            customColor: nil,
            transparency: 0.60
        )
        #expect(composed.transparency == 0.60, "current opacity wins over the snapshot")
        #expect(composed.colorKey == .blue, "current color wins over the snapshot")
        #expect(composed.title == "keep me", "non-appearance fields survive composition")
        #expect(composed.alwaysOnTop == true, "non-appearance fields survive composition")
    }
}
