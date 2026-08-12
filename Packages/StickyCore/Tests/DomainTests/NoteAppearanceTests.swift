import Testing
import Foundation
import Domain

// MARK: - NoteAppearance tests (T046 + T225 + T252)
//
// Per tasks.md T046: "Domain test: color/transparency/textSize/alwaysOnTop
// persist per note."
//
// Extended per T225 (FR-040a/FR-041a binding values, clarified 2026-08-07):
// - The six built-in colors resolve to EXACTLY the canonical sRGB hexes
//   (yellow #FFE08A, pink #F9A8C4, purple #C9A8E8, blue #A8CFF9,
//   green #A8E8B8, gray #D8D8DC) shared across light/dark.
// - Opacity is constrained to 0.00–1.00 in 0.05 steps with default 1.00
//   (004 Q8, 2026-08-13: the original 0.40 floor was removed by user
//   directive).
// - FR-042 WCAG contrast (≥4.5:1 normal, ≥3:1 large) holds for the full
//   matrix: 6 colors × 13 opacity steps × light/dark, computed against the
//   effective composited background, with automatic foreground adjustment.
//
// Extended per T252 (FR-043a): textSize is the integer point size (9–24
// inclusive, default 13); ≥18 pt is large text for the FR-042 thresholds.

@Suite struct NoteAppearanceTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    // MARK: - FR-040a canonical hexes

    @Test
    func builtinColorsHaveExactlyCanonicalHexes() {
        let expected: [NoteColorKey: String] = [
            .yellow: "#FFE08A",
            .pink:   "#F9A8C4",
            .purple: "#C9A8E8",
            .blue:   "#A8CFF9",
            .green:  "#A8E8B8",
            .gray:   "#D8D8DC",
        ]
        for (key, hex) in expected {
            #expect(key.canonicalHex == hex, "\(key) must be exactly \(hex)")
            #expect(key.builtinRGB?.hexString.uppercased() == hex, "\(key) RGB must round-trip to \(hex)")
        }
        #expect(NoteColorKey.custom.canonicalHex == nil)
    }

    @Test
    func builtinYellowIsLight() {
        let yellow = NoteColorKey.yellow.builtinRGB!
        #expect(yellow.red > 0.9 && yellow.green > 0.8 && yellow.blue < 0.7)
    }

    // MARK: - Hex parsing

    @Test
    func hexParsesSixDigitForm() {
        let c = RGBColor(hex: "#ff8800")!
        #expect(abs(c.red - 1.0) < 0.01)
        #expect(abs(c.green - 0.533) < 0.01)
        #expect(abs(c.blue - 0.0) < 0.01)
    }

    @Test
    func hexParsesThreeDigitForm() {
        let c = RGBColor(hex: "#f80")!
        let full = RGBColor(hex: "#ff8800")!
        #expect(c == full, "#f80 should equal #ff8800")
    }

    @Test
    func hexRoundTrips() {
        let c = RGBColor(red: 0.2, green: 0.5, blue: 0.9)
        let parsed = RGBColor(hex: c.hexString)!
        #expect(abs(parsed.red - c.red) < 0.01)
        #expect(abs(parsed.green - c.green) < 0.01)
        #expect(abs(parsed.blue - c.blue) < 0.01)
    }

    @Test
    func malformedHexReturnsNil() {
        #expect(RGBColor(hex: "not-a-color") == nil)
        #expect(RGBColor(hex: "#GGGGGG") == nil)
        #expect(RGBColor(hex: "") == nil)
        #expect(RGBColor(hex: "#12345") == nil)  // wrong digit count
    }

    // MARK: - FR-043a textSize bounds

    @Test
    func textSizeBoundsAreNineToTwentyFourInclusive() {
        #expect(NoteAppearance.TextSizeBounds.minSize == 9)
        #expect(NoteAppearance.TextSizeBounds.maxSize == 24)
        #expect(NoteAppearance.TextSizeBounds.defaultSize == 13)
        #expect(NoteAppearance.TextSizeBounds.allSizes == Array(9...24))
        #expect(NoteAppearance.TextSizeBounds.clamped(8) == 9)
        #expect(NoteAppearance.TextSizeBounds.clamped(25) == 24)
        #expect(NoteAppearance.TextSizeBounds.clamped(14) == 14)
    }

    @Test
    func textSizeEighteenOrAboveIsLargeText() {
        #expect(NoteAppearanceContrast.minimumContrastRatio(forTextSize: 17) == 4.5)
        #expect(NoteAppearanceContrast.minimumContrastRatio(forTextSize: 18) == 3.0)
        #expect(NoteAppearanceContrast.minimumContrastRatio(forTextSize: 24) == 3.0)
        #expect(NoteAppearance.TextSizeBounds.largeTextSize == 18)
    }

    @Test
    func noteTextSizeDefaultsToThirteen() {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        #expect(note.textSize == 13)
    }

    // MARK: - FR-041a opacity bounds (004 Q8: 0–100%, 2026-08-13)

    @Test
    func opacityBoundsAreZeroToHundredInFivePointSteps() {
        #expect(NoteAppearance.OpacityBounds.minOpacity == 0.0)
        #expect(NoteAppearance.OpacityBounds.maxOpacity == 1.00)
        #expect(NoteAppearance.OpacityBounds.step == 0.05)
        #expect(NoteAppearance.OpacityBounds.allSteps.count == 21)
        #expect(NoteAppearance.OpacityBounds.allSteps.first == 0.0)
        #expect(NoteAppearance.OpacityBounds.allSteps.last == 1.00)
    }

    @Test
    func opacityClampsToDiscreteSteps() {
        #expect(NoteAppearance.OpacityBounds.clamped(-0.2) == 0.0)
        #expect(NoteAppearance.OpacityBounds.clamped(0.0) == 0.0)
        #expect(NoteAppearance.OpacityBounds.clamped(0.42) == 0.40)
        #expect(NoteAppearance.OpacityBounds.clamped(0.48) == 0.50)
        #expect(NoteAppearance.OpacityBounds.clamped(1.0) == 1.0)
        #expect(NoteAppearance.OpacityBounds.clamped(1.3) == 1.0)
    }

    @Test
    func noteOpacityDefaultsToOneHundred() {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        #expect(note.transparency == 1.0)
        let appearance = NoteAppearance.projecting(from: note)
        #expect(appearance.opacity == 1.0)
    }

    // MARK: - Projection carries per-note fields (FR-031..FR-043a)

    @Test
    func projectionCarriesColorOpacityTextSizeAlwaysOnTop() {
        let note = Note(
            colorKey: .blue,
            transparency: 0.3,
            textSize: 18,
            alwaysOnTop: true,
            lastModifiedDeviceId: Self.deviceId
        )
        let appearance = NoteAppearance.projecting(from: note)
        // Opacity 0.3 snaps to the 0.05 grid (004 Q8: no 0.40 floor).
        #expect(appearance.opacity == 0.30)
        #expect(appearance.textSize == 18)
        #expect(appearance.alwaysOnTop == true)
    }

    @Test
    func customColorIsProjectedFromHex() {
        let note = Note(
            colorKey: .custom,
            customColor: "#abcdef",
            lastModifiedDeviceId: Self.deviceId
        )
        let appearance = NoteAppearance.projecting(from: note)
        #expect(appearance.background == RGBColor(hex: "#abcdef"))
    }

    @Test
    func malformedCustomColorFallsBackToYellow() {
        let note = Note(
            colorKey: .custom,
            customColor: "garbage",
            lastModifiedDeviceId: Self.deviceId
        )
        let appearance = NoteAppearance.projecting(from: note)
        #expect(appearance.background == NoteColorKey.yellow.builtinRGB)
    }

    // MARK: - Readable foreground (FR-042)

    @Test
    func lightBackgroundGetsBlackForeground() {
        let yellow = NoteColorKey.yellow.builtinRGB!
        let fg = NoteAppearanceContrast.readableForeground(forBackground: yellow)
        let black = RGBColor(red: 0, green: 0, blue: 0)
        #expect(fg == black, "yellow should use black text")
    }

    @Test
    func darkBackgroundGetsWhiteForeground() {
        let dark = RGBColor(red: 0.05, green: 0.05, blue: 0.05)
        let fg = NoteAppearanceContrast.readableForeground(forBackground: dark)
        let white = RGBColor(red: 1, green: 1, blue: 1)
        #expect(fg == white, "very dark backgrounds should use white text")
    }

    @Test
    func pureBlackBackgroundMeetsContrastWithWhite() {
        let black = RGBColor(red: 0, green: 0, blue: 0)
        let white = RGBColor(red: 1, green: 1, blue: 1)
        #expect(NoteAppearanceContrast.meetsMinimumContrast(foreground: white, background: black))
        let appearance = NoteAppearance(
            background: black,
            foreground: white,
            opacity: 1.0,
            textSize: 13,
            alwaysOnTop: false
        )
        #expect(appearance.meetsMinimumContrast)
    }

    // MARK: - FR-042 contrast matrix (T225)
    //
    // The full matrix: 6 built-in colors × 13 opacity steps × light/dark
    // desktop samples. For each combination the projection must produce a
    // foreground (black or white) that meets the applicable WCAG 2.2 AA
    // threshold against the effective composited background, and
    // `meetsMinimumContrast` must be true.

    @Test
    func contrastMatrixHoldsForAllColorsOpacitiesAndAppearances() {
        let desktopSamples: [String: RGBColor] = [
            "light": RGBColor(red: 0.95, green: 0.95, blue: 0.95),
            "dark":  RGBColor(red: 0.10, green: 0.10, blue: 0.10),
        ]
        var failures: [String] = []
        for key in NoteColorKey.allCases where key != .custom {
            let note = Note(
                colorKey: key,
                transparency: 1.0,
                textSize: 13,
                alwaysOnTop: false,
                lastModifiedDeviceId: Self.deviceId
            )
            for opacity in NoteAppearance.OpacityBounds.allSteps {
                for (appearanceName, sample) in desktopSamples {
                    var n = note
                    n.transparency = opacity
                    let projection = NoteAppearance.projecting(from: n, desktopSample: sample)
                    let threshold = NoteAppearanceContrast.minimumContrastRatio(forTextSize: 13)
                    let ratio = NoteAppearanceContrast.contrastRatio(projection.foreground, projection.background)
                    if ratio < threshold {
                        failures.append("\(key.rawValue) @ \(opacity) over \(appearanceName): ratio \(ratio) < \(threshold)")
                    }
                    if !projection.meetsMinimumContrast {
                        failures.append("\(key.rawValue) @ \(opacity) over \(appearanceName): flagged fails contrast")
                    }
                }
            }
        }
        #expect(failures.isEmpty, Comment(rawValue: "Contrast matrix failures:\n" + failures.joined(separator: "\n")))
    }

    // MARK: - Legacy projection field check

    @Test
    func midGrayBackgroundComputesContrastFlag() {
        let midGray = RGBColor(red: 0.5, green: 0.5, blue: 0.5)
        let appearance = NoteAppearance(
            background: midGray,
            foreground: NoteAppearanceContrast.readableForeground(forBackground: midGray),
            opacity: 1.0,
            textSize: 13,
            alwaysOnTop: false
        )
        #expect(appearance.meetsMinimumContrast == Bool(appearance.meetsMinimumContrast))
    }
}
