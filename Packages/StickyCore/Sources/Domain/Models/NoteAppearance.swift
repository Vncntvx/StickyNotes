import Foundation

// MARK: - NoteAppearance (T050 / T234 / T257)
//
// Per tasks.md T050/T234/T257 and data-model.md §Note / spec FR-031..FR-043a:
// - Built-in colors: Yellow/Pink/Purple/Blue/Green/Gray + custom hex. Each
//   built-in has ONE canonical sRGB hex shared across light/dark (FR-040a,
//   clarified 2026-08-07): yellow #FFE08A, pink #F9A8C4, purple #C9A8E8,
//   blue #A8CFF9, green #A8E8B8, gray #D8D8DC. Any change to a canonical
//   value must update the FR-042 contrast matrix tests in the same change.
// - Opacity (FR-041a): constrained to 0.40–1.00 inclusive in 0.05 steps,
//   default 1.00. The persisted `Note.transparency` field name is retained
//   but its semantic is opacity. Below 1.00 the contrast logic validates
//   against the effective composited background (note color at the chosen
//   opacity over the desktop).
// - Per-note text size (FR-043a): integer point size 9–24 inclusive, 1-pt
//   steps, default 13; ≥18 pt is large text for the FR-042 thresholds.
// - Per-note Always-on-Top (FR-036).
// - Custom colors failing contrast are adjusted or rejected (FR-042). The
//   contrast check lives here (Domain) so it's testable without UI; the App
//   layer applies the foreground color the check selects.
//
// The `Note` struct (Models.swift) carries the raw persisted appearance
// fields; `NoteAppearance` is the *projection + rules* layer that derives a
// concrete background RGB and a readable foreground.

// MARK: - Built-in note colors (FR-040a canonical sRGB hexes)

public extension NoteColorKey {
    /// The canonical sRGB hex for this built-in color (FR-040a, clarified
    /// 2026-08-07). Returns `nil` for `.custom` (the caller consults
    /// `Note.customColor`). These exact values are the deterministic input
    /// for the FR-042 contrast matrix tests; changing one requires updating
    /// `NoteAppearanceBindingTests` in the same change (constitution IV).
    var canonicalHex: String? {
        switch self {
        case .yellow: return "#FFE08A"
        case .pink:   return "#F9A8C4"
        case .purple: return "#C9A8E8"
        case .blue:   return "#A8CFF9"
        case .green:  return "#A8E8B8"
        case .gray:   return "#D8D8DC"
        case .custom: return nil
        }
    }

    /// The concrete RGB for this built-in color (parsed from the canonical
    /// hex). Returns `nil` for `.custom`.
    var builtinRGB: RGBColor? {
        canonicalHex.flatMap { RGBColor(hex: $0) }
    }
}

// MARK: - RGBColor

/// A linear RGB color in 0...1 per channel. Foundation-only (no SwiftUI/
/// CoreGraphics) so it's testable in the Domain layer.
public struct RGBColor: Sendable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        precondition((0...1).contains(red),   "red out of range")
        precondition((0...1).contains(green), "green out of range")
        precondition((0...1).contains(blue),  "blue out of range")
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses a `#RRGGBB` or `#RGB` hex string. Returns `nil` on malformed
    /// input. The leading `#` is optional; channels may be 1 or 2 hex digits.
    public init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard !s.isEmpty else { return nil }
        let scanner = Scanner(string: s)
        scanner.charactersToBeSkipped = []
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value) else { return nil }
        let digits = s.count
        switch digits {
        case 3:
            // #RGB → #RRGGBB (each digit doubled)
            let r = Double((value >> 8) & 0xF) / 15.0
            let g = Double((value >> 4) & 0xF) / 15.0
            let b = Double( value       & 0xF) / 15.0
            self = RGBColor(red: r, green: g, blue: b)
        case 6:
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >>  8) & 0xFF) / 255.0
            let b = Double( value        & 0xFF) / 255.0
            self = RGBColor(red: r, green: g, blue: b)
        default:
            return nil
        }
    }

    /// Encodes back to a `#RRGGBB` hex string (always 6 digits, lowercase).
    public var hexString: String {
        let r = Int((red   * 255.0).rounded())
        let g = Int((green * 255.0).rounded())
        let b = Int((blue  * 255.0).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

// MARK: - Contrast + readable foreground (FR-042)

public enum NoteAppearanceContrast {
    /// WCAG 2.1 relative luminance of an sRGB color.
    public static func relativeLuminance(_ c: RGBColor) -> Double {
        func channel(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
    }

    /// WCAG contrast ratio between two colors (1.0 .. 21.0).
    public static func contrastRatio(_ a: RGBColor, _ b: RGBColor) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        let lighter = max(la, lb)
        let darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// The minimum contrast ratio the foreground must achieve against the
    /// note background. WCAG AA for normal text is 4.5; large text
    /// (≥18 pt, FR-043a) requires 3:1 per WCAG 2.2 AA.
    public static let minimumContrastRatio: Double = 4.5
    public static let largeTextContrastRatio: Double = 3.0

    /// The contrast threshold for the given text size (FR-043a: text ≥18 pt
    /// is large text and uses the 3:1 threshold).
    public static func minimumContrastRatio(forTextSize points: Int) -> Double {
        points >= NoteAppearance.TextSizeBounds.largeTextSize
            ? largeTextContrastRatio
            : minimumContrastRatio
    }

    /// Returns the foreground (black or white) that achieves the higher
    /// contrast against the given background.
    public static func readableForeground(forBackground bg: RGBColor) -> RGBColor {
        let black = RGBColor(red: 0, green: 0, blue: 0)
        let white = RGBColor(red: 1, green: 1, blue: 1)
        return contrastRatio(bg, black) >= contrastRatio(bg, white) ? black : white
    }

    /// Returns `true` if `foreground` meets the minimum contrast against
    /// `background` for the given text size. Used to validate custom colors
    /// (FR-042).
    public static func meetsMinimumContrast(
        foreground: RGBColor,
        background: RGBColor,
        textSizePoints: Int = NoteAppearance.TextSizeBounds.defaultSize
    ) -> Bool {
        contrastRatio(foreground, background) >= minimumContrastRatio(forTextSize: textSizePoints)
    }
}

// MARK: - NoteAppearance projection

/// A derived, ready-to-render appearance for a note. Carries the concrete
/// background RGB (built-in or custom), the chosen foreground (black or
/// white per contrast), the opacity (FR-041a), text size (FR-043a), and
/// Always-on-Top.
///
/// This is a *projection* of `Note`'s persisted fields — it is never stored.
public struct NoteAppearance: Sendable, Equatable {
    /// Text-size bounds (FR-043a): 9–24 pt inclusive, 1-pt steps.
    public enum TextSizeBounds {
        public static let minSize = 9
        public static let maxSize = 24
        public static let defaultSize = 13
        /// Text ≥18 pt is large text for the FR-042 thresholds.
        public static let largeTextSize = 18

        /// The full set of discrete text sizes (16 steps).
        public static let allSizes: [Int] = Array(minSize...maxSize)

        /// Clamps + validates a raw value into the allowed range.
        public static func clamped(_ value: Int) -> Int {
            min(max(value, minSize), maxSize)
        }
    }

    /// Opacity bounds (FR-041a; 004 Q8 2026-08-13: 0.00–1.00 — the
    /// original 0.40 floor was removed by user directive, the range is
    /// now full 0–100%).
    public enum OpacityBounds {
        public static let minOpacity = 0.0
        public static let maxOpacity = 1.00
        public static let step = 0.05

        /// The full set of discrete opacity values (21 steps).
        public static let allSteps: [Double] = {
            // Integer-percent arithmetic (0..100 step 5) so each value is
            // the exact same Double as the literal (e.g. 0.60).
            let startPercent = Int(minOpacity * 100)   // 0
            let endPercent = Int(maxOpacity * 100)     // 100
            let stepPercent = Int(step * 100)          // 5
            return stride(from: startPercent, through: endPercent, by: stepPercent)
                .map { Double($0) / 100.0 }
        }()

        /// Clamps a raw value into the allowed discrete steps. Integer-
        /// percent arithmetic so every step equals the exact Double literal
        /// (e.g. `clamped(0.30) == 0.30` — naive `0.3 / 0.05` drift gives
        /// 0.30000000000000004).
        public static func clamped(_ value: Double) -> Double {
            let percent = Int((value * 100).rounded())
            let stepPercent = Int(step * 100)
            let clampedPercent = min(
                max(percent, Int(minOpacity * 100)),
                Int(maxOpacity * 100)
            )
            let stepped = Int((Double(clampedPercent) / Double(stepPercent)).rounded()) * stepPercent
            return Double(min(max(stepped, 0), 100)) / 100.0
        }
    }

    public var background: RGBColor
    public var foreground: RGBColor
    /// Effective opacity 0.00–1.00 in 0.05 steps (FR-041a; 004 Q8). The
    /// persisted field is named `transparency`; this is its semantic value.
    public var opacity: Double
    /// Per-note text size in points, 9–24 (FR-043a).
    public var textSize: Int
    public var alwaysOnTop: Bool

    public init(background: RGBColor, foreground: RGBColor, opacity: Double, textSize: Int, alwaysOnTop: Bool) {
        self.background = background
        self.foreground = foreground
        self.opacity = OpacityBounds.clamped(opacity)
        self.textSize = TextSizeBounds.clamped(textSize)
        self.alwaysOnTop = alwaysOnTop
    }

    /// Composites a note background over a desktop sample at the given
    /// opacity. Used for FR-042 contrast validation below 100% opacity
    /// (FR-041a: the effective composited background is
    /// noteColor@opacity over the desktop).
    public static func compositedBackground(
        noteColor: RGBColor,
        opacity: Double,
        desktopSample: RGBColor
    ) -> RGBColor {
        let o = OpacityBounds.clamped(opacity)
        return RGBColor(
            red:   noteColor.red   * o + desktopSample.red   * (1 - o),
            green: noteColor.green * o + desktopSample.green * (1 - o),
            blue:  noteColor.blue  * o + desktopSample.blue  * (1 - o)
        )
    }

    /// Derives the appearance from a `Note`. For `.custom` colors, the
    /// `customColor` hex is parsed; if it's malformed, the note falls back
    /// to the default yellow background (the App layer surfaces a warning).
    /// The opacity is clamped to the FR-041a discrete range; the text size
    /// is clamped to the FR-043a range. Foreground contrast is computed
    /// against the effective composited background (note color at the
    /// chosen opacity over a default desktop sample) when opacity < 1.0.
    public static func projecting(from note: Note, desktopSample: RGBColor? = nil) -> NoteAppearance {
        let bg: RGBColor
        if let builtin = note.colorKey.builtinRGB {
            bg = builtin
        } else if let hex = note.customColor, let parsed = RGBColor(hex: hex) {
            bg = parsed
        } else {
            // `.custom` with missing/invalid hex → fall back to yellow.
            bg = NoteColorKey.yellow.builtinRGB ?? RGBColor(red: 1, green: 1, blue: 1)
        }
        let opacity = OpacityBounds.clamped(note.transparency)
        let effectiveBG: RGBColor
        if opacity < OpacityBounds.maxOpacity {
            // Below 100% opacity: validate against the effective composited
            // background (note color at chosen opacity over the desktop).
            let sample = desktopSample ?? RGBColor(red: 0.45, green: 0.45, blue: 0.45)
            effectiveBG = compositedBackground(noteColor: bg, opacity: opacity, desktopSample: sample)
        } else {
            effectiveBG = bg
        }
        let fg = NoteAppearanceContrast.readableForeground(forBackground: effectiveBG)
        return NoteAppearance(
            background: effectiveBG,
            foreground: fg,
            opacity: opacity,
            textSize: note.textSize,
            alwaysOnTop: note.alwaysOnTop
        )
    }

    /// Returns `true` if the effective background achieves the minimum
    /// contrast for the note's text size with at least one of black/white
    /// foreground. If `false`, the App layer must adjust the color or
    /// reject it with an explanation (FR-042).
    public var meetsMinimumContrast: Bool {
        let black = RGBColor(red: 0, green: 0, blue: 0)
        let white = RGBColor(red: 1, green: 1, blue: 1)
        let threshold = NoteAppearanceContrast.minimumContrastRatio(forTextSize: textSize)
        return NoteAppearanceContrast.contrastRatio(black, background) >= threshold
            || NoteAppearanceContrast.contrastRatio(white, background) >= threshold
    }
}
