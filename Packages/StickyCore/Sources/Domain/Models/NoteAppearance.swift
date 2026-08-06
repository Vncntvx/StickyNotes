import Foundation

// MARK: - NoteAppearance (T050)
//
// Per tasks.md T050 and data-model.md §Note / spec FR-031..FR-042:
// - Built-in colors: Yellow/Pink/Purple/Blue/Green/Gray + custom hex.
// - Transparency (0.0 opaque .. 1.0).
// - Per-note text size (small/regular/large/extraLarge).
// - Per-note Always-on-Top (FR-036).
// - Custom colors failing contrast are adjusted or rejected (FR-042, plan
//   §Accessibility). The contrast check lives here (Domain) so it's testable
//   without UI; the App layer applies the foreground color the check selects.
//
// The `Note` struct (Models.swift) carries the raw persisted appearance
// fields; `NoteAppearance` is the *projection + rules* layer that derives a
// concrete background RGB and a readable foreground.

// MARK: - Built-in note colors
//
// Per spec FR-031. The hex values are the classic macOS sticky-note palette
// tuned for readability with dark foreground text. They are intentionally
// not localized (constitution XIV — colors are stable identifiers).

public extension NoteColorKey {
    /// The concrete RGB for this built-in color. Returns `nil` for
    /// `.custom` (the caller consults `Note.customColor`).
    var builtinRGB: RGBColor? {
        switch self {
        case .yellow: return RGBColor(red: 1.00, green: 0.94, blue: 0.56)  // #FFF18F
        case .pink:   return RGBColor(red: 1.00, green: 0.74, blue: 0.83)  // #FFBDD4
        case .purple: return RGBColor(red: 0.90, green: 0.78, blue: 0.96)  // #E6C7F5
        case .blue:   return RGBColor(red: 0.78, green: 0.90, blue: 1.00)  // #C7E6FF
        case .green:  return RGBColor(red: 0.80, green: 0.95, blue: 0.78)  // #CCF2C7
        case .gray:   return RGBColor(red: 0.90, green: 0.90, blue: 0.90)  // #E6E6E6
        case .custom: return nil
        }
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
//
// Per WCAG 2.1 relative luminance + contrast ratio. The Domain layer decides
// black-vs-white foreground based on the background's luminance; custom
// colors below the contrast threshold are flagged so the App layer can
// adjust or reject them (FR-042).

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
    /// note background. WCAG AA for normal text is 4.5; we use the same.
    public static let minimumContrastRatio: Double = 4.5

    /// Returns the foreground (black or white) that achieves the higher
    /// contrast against the given background.
    public static func readableForeground(forBackground bg: RGBColor) -> RGBColor {
        let black = RGBColor(red: 0, green: 0, blue: 0)
        let white = RGBColor(red: 1, green: 1, blue: 1)
        return contrastRatio(bg, black) >= contrastRatio(bg, white) ? black : white
    }

    /// Returns `true` if `foreground` meets the minimum contrast against
    /// `background`. Used to validate custom colors (FR-042).
    public static func meetsMinimumContrast(foreground: RGBColor, background: RGBColor) -> Bool {
        contrastRatio(foreground, background) >= minimumContrastRatio
    }
}

// MARK: - NoteAppearance projection

/// A derived, ready-to-render appearance for a note. Carries the concrete
/// background RGB (built-in or custom), the chosen foreground (black or
/// white per contrast), the transparency, text size, and Always-on-Top.
///
/// This is a *projection* of `Note`'s persisted fields — it is never stored.
public struct NoteAppearance: Sendable, Equatable {
    public var background: RGBColor
    public var foreground: RGBColor
    public var transparency: Double
    public var textSize: TextSize
    public var alwaysOnTop: Bool

    public init(background: RGBColor, foreground: RGBColor, transparency: Double, textSize: TextSize, alwaysOnTop: Bool) {
        self.background = background
        self.foreground = foreground
        self.transparency = transparency
        self.textSize = textSize
        self.alwaysOnTop = alwaysOnTop
    }

    /// Derives the appearance from a `Note`. For `.custom` colors, the
    /// `customColor` hex is parsed; if it's malformed, the note falls back
    /// to the default yellow background (the App layer surfaces a warning).
    public static func projecting(from note: Note) -> NoteAppearance {
        let bg: RGBColor
        if let builtin = note.colorKey.builtinRGB {
            bg = builtin
        } else if let hex = note.customColor, let parsed = RGBColor(hex: hex) {
            bg = parsed
        } else {
            // `.custom` with missing/invalid hex → fall back to yellow.
            bg = NoteColorKey.yellow.builtinRGB ?? RGBColor(red: 1, green: 1, blue: 1)
        }
        let fg = NoteAppearanceContrast.readableForeground(forBackground: bg)
        return NoteAppearance(
            background: bg,
            foreground: fg,
            transparency: note.transparency,
            textSize: note.textSize,
            alwaysOnTop: note.alwaysOnTop
        )
    }

    /// Returns `true` if the background achieves minimum contrast with at
    /// least one of black/white foreground. If `false`, the App layer must
    /// adjust the color or reject it with an explanation (FR-042).
    public var meetsMinimumContrast: Bool {
        let black = RGBColor(red: 0, green: 0, blue: 0)
        let white = RGBColor(red: 1, green: 1, blue: 1)
        return NoteAppearanceContrast.meetsMinimumContrast(foreground: black, background: background)
            || NoteAppearanceContrast.meetsMinimumContrast(foreground: white, background: background)
    }
}
