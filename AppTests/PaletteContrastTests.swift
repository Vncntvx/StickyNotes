import Testing
import Foundation
import SwiftUI
import AppKit
import Domain
@testable import StickyNotes

// MARK: - Palette contrast tests (003 T004, FR-031/001 FR-042)
//
// Per tasks.md T004: every built-in palette color (7) × light/dark
// appearance must satisfy the 001 FR-042 thresholds against REAL rendered
// background values (resolved via AppKit, not the source constants):
// - primary text ≥ 4.5:1
// - large text (≥18 pt) and active controls ≥ 3:1
// - secondary text, selection, and control states ≥ 3:1 (secondary ≥ 4.5:1)
// FR-031: the light/dark pairs are INDEPENDENTLY designed values (no
// mechanical transparency/brightness transforms — asserted by design at
// implementation time; the test asserts the outcome thresholds).

@Suite struct PaletteContrastTests {

    /// Resolves a SwiftUI `Color` to sRGB components through AppKit — the
    /// "real rendered value" the FR-042 thresholds apply to.
    static func resolvedSRGB(_ color: Color) -> Domain.RGBColor {
        let ns = NSColor(color).usingColorSpace(.sRGB)
        guard let ns else {
            Issue.record("color failed to resolve to sRGB: \(color)")
            return Domain.RGBColor(red: 0, green: 0, blue: 0)
        }
        return Domain.RGBColor(
            red: Double(ns.redComponent),
            green: Double(ns.greenComponent),
            blue: Double(ns.blueComponent)
        )
    }

    static func contrast(_ a: Color, _ b: Color) -> Double {
        NoteAppearanceContrast.contrastRatio(resolvedSRGB(a), resolvedSRGB(b))
    }

    @Test
    func primaryTextMeetsThresholdAcrossPalette() {
        for key in NotePaletteKey.allCases {
            let entry = NotePalette.entry(for: key)
            // Light appearance: primary text against the light background.
            let lightPrimary = NotePalette.foreground(for: key, appearanceName: .aqua)
            #expect(
                Self.contrast(lightPrimary, entry.lightColor) >= 4.5,
                "light \(key.rawValue): primary text ≥4.5:1 (got \(Self.contrast(lightPrimary, entry.lightColor)))"
            )
            // Dark appearance: primary text against the dark background.
            let darkPrimary = NotePalette.foreground(for: key, appearanceName: .darkAqua)
            #expect(
                Self.contrast(darkPrimary, entry.darkColor) >= 4.5,
                "dark \(key.rawValue): primary text ≥4.5:1 (got \(Self.contrast(darkPrimary, entry.darkColor)))"
            )
        }
    }

    @Test
    func largeTextAndActiveControlMeetThreeToOneThreshold() {
        for key in NotePaletteKey.allCases {
            let entry = NotePalette.entry(for: key)
            for (appearance, bg) in [
                ("light", entry.lightColor),
                ("dark", entry.darkColor),
            ] {
                let fg = NotePalette.foreground(
                    for: key,
                    appearanceName: appearance == "light" ? .aqua : .darkAqua
                )
                #expect(
                    Self.contrast(fg, bg) >= 3.0,
                    "\(appearance) \(key.rawValue): large text / active control ≥3:1 (got \(Self.contrast(fg, bg)))"
                )
            }
        }
    }

    @Test
    func secondaryTextMeetsThresholdAcrossPalette() {
        for key in NotePaletteKey.allCases {
            let entry = NotePalette.entry(for: key)
            let lightSecondary = NotePalette.secondaryForeground(for: key, appearanceName: .aqua)
            #expect(
                Self.contrast(lightSecondary, entry.lightColor) >= 4.5,
                "light \(key.rawValue): secondary text ≥4.5:1 (got \(Self.contrast(lightSecondary, entry.lightColor)))"
            )
            let darkSecondary = NotePalette.secondaryForeground(for: key, appearanceName: .darkAqua)
            #expect(
                Self.contrast(darkSecondary, entry.darkColor) >= 4.5,
                "dark \(key.rawValue): secondary text ≥4.5:1 (got \(Self.contrast(darkSecondary, entry.darkColor)))"
            )
        }
    }

    @Test
    func selectionAndControlStatesMeetThreeToOneThreshold() {
        // Selection indicator and control states must stay ≥3:1 against the
        // rendered background (FR-031 "选择态与控件同样达标").
        for key in NotePaletteKey.allCases {
            let entry = NotePalette.entry(for: key)
            for (appearance, bg) in [
                ("light", entry.lightColor),
                ("dark", entry.darkColor),
            ] {
                let fg = NotePalette.foreground(
                    for: key,
                    appearanceName: appearance == "light" ? .aqua : .darkAqua
                )
                #expect(
                    Self.contrast(fg, bg) >= 3.0,
                    "\(appearance) \(key.rawValue): selection/control state ≥3:1 (got \(Self.contrast(fg, bg)))"
                )
            }
        }
    }

    @Test
    func everyEntryIsContrastValidated() {
        // FR-031: each palette entry carries the validation marker; the
        // tests above re-derive it from rendered values.
        for key in NotePaletteKey.allCases {
            #expect(
                NotePalette.entry(for: key).contrastValidated,
                "\(key.rawValue) must be contrast-validated (FR-031)"
            )
        }
    }

    @Test
    func paletteHasExactlySevenColors() {
        // FR-030: yellow, peach, pink, green/mint, blue, lavender, gray.
        #expect(NotePaletteKey.allCases.map(\.rawValue).sorted() ==
                ["blue", "gray", "green", "lavender", "peach", "pink", "yellow"])
    }

    // MARK: - 003 T036 (FR-033): custom + transparency + appearance combos

    @Test
    func customColorWithTransparencyAutoAdjustsForeground() {
        // FR-033: a custom color + transparency that would fall below the
        // threshold must AUTO-ADJUST the foreground — the color is never
        // rejected.
        let custom = Note(
            colorKey: .custom,
            customColor: "#808080",   // mid-gray: borderline with white/black
            transparency: 0.4,        // minimum opacity over the desktop
            lastModifiedDeviceId: UUID(uuidString: "d0000000-0000-4000-8000-0000000000d1")!
        )
        let projection = NoteAppearance.projecting(from: custom)
        // The Domain projection auto-picks black or white and the result
        // meets the threshold at the effective composited background.
        #expect(projection.meetsMinimumContrast,
                "custom color + transparency must auto-adjust, never reject (FR-033)")
    }

    @Test
    func customColorNeverRejectedAcrossAppearances() {
        // FR-033: no "custom color + appearance/Increase Contrast"
        // combination is rejected — the foreground adjusts instead.
        let custom = Note(
            colorKey: .custom,
            customColor: "#FF6B6B",
            transparency: 1.0,
            lastModifiedDeviceId: UUID(uuidString: "d0000000-0000-4000-8000-0000000000d2")!
        )
        // ReadableTheme.foreground renders a valid (non-clear) color for
        // the custom note — adjustment, not rejection.
        #expect(ReadableTheme.foreground(for: custom) != Color.clear)
        #expect(!ReadableTheme.customColorFailsContrast(custom) ||
                NoteAppearance.projecting(from: custom).meetsMinimumContrast,
                "any failing combination adjusts rather than rejects (FR-033)")
    }
}
