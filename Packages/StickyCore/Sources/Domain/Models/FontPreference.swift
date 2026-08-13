import Foundation

// MARK: - FontPreference (T142)
//
// Per tasks.md T142 and spec FR-043: a global font preference with Chinese +
// English fallback selection for unsupported glyphs. Persisted device-locally
// (standard UserDefaults via the App layer); never synchronized, never in
// canonical JSON (it is a device-level preference, not note content).
//
// The model is Foundation-only and language-neutral: it stores font family
// *names*, not localized identifiers. When a glyph is unsupported by the
// primary family, the App layer falls back to the secondary family (and the
// system fallback chain) per FR-043.
//
// T147 (Domain test): FontPreference persistence + Chinese/English fallback
// selection for unsupported glyphs per FR-043.

/// The global font preference (FR-043, clarified 2026-08-07).
public struct FontPreference: Sendable, Codable, Equatable, Hashable {
    /// The primary (English/Latin) font family name. `nil` = system default.
    public var primaryFamily: String?
    /// The fallback (Chinese/CJK) font family name. `nil` = system default
    /// (e.g. PingFang SC on macOS).
    public var fallbackFamily: String?

    public init(primaryFamily: String? = nil, fallbackFamily: String? = nil) {
        self.primaryFamily = primaryFamily
        self.fallbackFamily = fallbackFamily
    }

    /// The system default preference: primary = the app's default UI font
    /// family, fallback = the CJK-complete PingFang SC family.
    public static let systemDefault = FontPreference(
        primaryFamily: "Helvetica Neue",
        fallbackFamily: "PingFang SC"
    )

    /// The family that should render a given text: if the text contains any
    /// CJK (Chinese/Japanese/Korean) scalar, the fallback family is used;
    /// otherwise the primary family. When either family is nil, the system
    /// default for that slot is substituted.
    ///
    /// FR-043: "Chinese + English with fallback". This is the *selection*
    /// rule; the actual font resolution (is a glyph supported?) happens in
    /// the App layer with `NSFont`/`CTFont` fallback chains.
    public func family(for text: String) -> String {
        if Self.containsCJK(text) {
            return fallbackFamily ?? FontPreference.systemDefault.fallbackFamily!
        }
        return primaryFamily ?? FontPreference.systemDefault.primaryFamily!
    }

    /// `true` if `text` contains any CJK scalar (Chinese/Japanese/Korean).
    public static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x2FFF,   // CJK radicals, punctuation, symbols
                 0x3000...0x303F,   // CJK punctuation
                 0x3040...0x30FF,   // Hiragana / Katakana
                 0x31F0...0x31FF,   // Katakana phonetic extensions
                 0x3400...0x4DBF,   // CJK unified ideographs ext A
                 0x4E00...0x9FFF,   // CJK unified ideographs
                 0xA000...0xA4CF,   // Yi
                 0xAC00...0xD7AF,   // Hangul
                 0xF900...0xFAFF,   // CJK compatibility ideographs
                 0xFF00...0xFFEF:   // halfwidth/fullwidth forms
                return true
            default:
                return false
            }
        }
    }
}
