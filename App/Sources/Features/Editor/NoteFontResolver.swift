import AppKit
import CoreText
import Domain

// MARK: - FontPreferenceStore (T308, FR-043)
//
// Device-local storage of the global font preference, shared by the Settings
// UI (`NoteFontSection`, Rev 2 — formerly `FontPreferenceView`) and the
// editor's font resolution (`NoteFontResolver`). The key/suite constants
// must not drift between the two consumers (the previous single-key usage
// lived inside `FontPreferenceView`).

public enum FontPreferenceStore {
    /// The standard UserDefaults domain used for device-local preferences.
    public static let suiteName: String? = nil
    /// The persistence key (JSON-encoded `FontPreference`).
    public static let key = "local.stickynotes.fontPreference"

    public static func load() -> FontPreference? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FontPreference.self, from: data)
    }

    public static func save(_ preference: FontPreference) {
        guard let data = try? JSONEncoder().encode(preference) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - NoteFontResolver (T308, FR-043)

/// Resolves the effective `NSFont` for note text from the stored global font
/// preference (FR-043): the primary (Latin) family for non-CJK text, the
/// fallback (CJK) family for CJK text, per coverage segment. With no stored
/// preference the resolver keeps the OS system font (the pre-FR-043
/// behavior); invalid family names degrade to the system font, and the
/// per-note text size (FR-043a) always wins for size.
public struct NoteFontResolver {
    /// The stored preference; `nil` = system font (no family override).
    public let preference: FontPreference?

    public init(preference: FontPreference?) {
        self.preference = preference
    }

    /// Loads the stored preference (system behavior when none stored).
    public static func load() -> NoteFontResolver {
        NoteFontResolver(preference: FontPreferenceStore.load())
    }

    /// The font for a whole text (one family per the FR-043 selection rule).
    public func font(
        size: CGFloat,
        traits: NSFontDescriptor.SymbolicTraits = [],
        for text: String
    ) -> NSFont {
        guard let preference else {
            return Self.systemFont(size: size, traits: traits)
        }
        let family = Self.family(preference: preference, for: text)
        return Self.font(family: family, size: size, traits: traits)
    }

    /// The NOMINAL body font for a typography: the PRIMARY family at the
    /// given size, never script-segmented. This is the todo checkbox's
    /// stable alignment font (PR1) — the optical offset between the real
    /// first-line baseline and the checkbox center is derived from it, so
    /// first-character bold / inline code / CJK / emoji formatting can never
    /// move the checkbox by changing the offset. The explicit form of the
    /// former `font(size:for: "")` edge case (an empty string made
    /// `family(for:)` return the primary family) — the alignment invariant
    /// must not depend on another API's empty-string semantics.
    public func nominalBodyFont(size: CGFloat) -> NSFont {
        guard let preference else {
            return Self.systemFont(size: size, traits: [])
        }
        let family = preference.primaryFamily ?? FontPreference.systemDefault.primaryFamily!
        return Self.font(family: family, size: size, traits: [])
    }

    /// Splits `text` into alternating non-CJK / CJK coverage segments, each
    /// with the font FR-043 assigns to it. Mixed Latin+CJK runs (e.g.
    /// "Hello 世界") therefore render English in the primary family and
    /// Chinese in the family the resolver assigns to CJK text within the
    /// same run (2026-08-14: the PRIMARY family when it provides CJK
    /// glyphs, else the fallback). With no stored preference the whole
    /// text is one system-font segment.
    public func segmentedFonts(
        text: String,
        size: CGFloat,
        traits: NSFontDescriptor.SymbolicTraits = []
    ) -> [(segment: String, font: NSFont)] {
        guard !text.isEmpty else { return [] }
        guard let preference else {
            return [(text, Self.systemFont(size: size, traits: traits))]
        }
        let scalars = Array(text.unicodeScalars)
        var segments: [(segment: String, font: NSFont)] = []
        var segmentStart = 0
        var segmentIsCJK = FontPreference.containsCJK(String(scalars[0]))
        for index in 1..<scalars.count {
            let isCJK = FontPreference.containsCJK(String(scalars[index]))
            if isCJK != segmentIsCJK {
                let segmentText = String(String.UnicodeScalarView(scalars[segmentStart..<index]))
                segments.append((segmentText, Self.font(family: Self.family(preference: preference, for: segmentText), size: size, traits: traits)))
                segmentStart = index
                segmentIsCJK = isCJK
            }
        }
        let finalText = String(String.UnicodeScalarView(scalars[segmentStart..<scalars.count]))
        segments.append((finalText, Self.font(family: Self.family(preference: preference, for: finalText), size: size, traits: traits)))
        return segments
    }

    // MARK: - FR-043 family selection (2026-08-14 CJK-aware)

    /// The family that renders `text`: non-CJK text uses the primary
    /// family; CJK text uses the PRIMARY family when it actually provides
    /// CJK glyphs (a user-chosen Chinese font must apply to Chinese text —
    /// matching the Settings preview's per-glyph `Font.custom` fallback),
    /// otherwise the fallback family (the FR-043 mixed-rendering
    /// guarantee for Latin-only primary families).
    private static func family(preference: FontPreference, for text: String) -> String {
        if FontPreference.containsCJK(text) {
            if let primary = preference.primaryFamily, fontSupportsCJK(primary) {
                return primary
            }
            return preference.fallbackFamily ?? FontPreference.systemDefault.fallbackFamily!
        }
        return preference.primaryFamily ?? FontPreference.systemDefault.primaryFamily!
    }

    // MARK: - CJK glyph coverage (cached per family)

    /// Whether a font family provides CJK glyphs, sampled on a small
    /// representative string. CoreText answers the "does this font cover
    /// Chinese" question the per-glyph fallback chain would ask; the
    /// result is cached per family (the list is bounded by the system font
    /// catalog). Locked — the resolver is called from the editor and the
    /// tests.
    private static let cjkCoverageLock = NSLock()
    private nonisolated(unsafe) static var cjkCoverageCache: [String: Bool] = [:]

    private static func fontSupportsCJK(_ family: String) -> Bool {
        cjkCoverageLock.lock()
        defer { cjkCoverageLock.unlock() }
        if let cached = cjkCoverageCache[family] { return cached }
        let font = CTFontCreateWithName(family as CFString, 13, nil)
        // 中文漢字 spans the common CJK unified ideographs the body text
        // actually uses; all four glyphs must resolve (missing glyphs
        // come back as 0).
        let sample = Array("中文漢字".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: sample.count)
        let supported = CTFontGetGlyphsForCharacters(font, sample, &glyphs, sample.count)
            && glyphs.allSatisfy { $0 != 0 }
        cjkCoverageCache[family] = supported
        return supported
    }

    // MARK: - Helpers

    private static func systemFont(
        size: CGFloat,
        traits: NSFontDescriptor.SymbolicTraits
    ) -> NSFont {
        guard !traits.isEmpty else { return NSFont.systemFont(ofSize: size) }
        return applying(traits, to: NSFont.systemFont(ofSize: size))
    }

    private static func font(
        family: String,
        size: CGFloat,
        traits: NSFontDescriptor.SymbolicTraits
    ) -> NSFont {
        let base = NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)
        guard !traits.isEmpty else { return base }
        return applying(traits, to: base)
    }

    /// Applies symbolic traits, synthesizing when the family lacks the
    /// face — italic on CJK (PingFang has no italic variant) must render
    /// oblique instead of silently falling back to the upright base font
    /// (2026-08-13 user report: ⌘I 失效).
    private static func applying(
        _ traits: NSFontDescriptor.SymbolicTraits,
        to base: NSFont
    ) -> NSFont {
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        if descriptor.symbolicTraits.contains(.bold) == traits.contains(.bold),
           descriptor.symbolicTraits.contains(.italic) == traits.contains(.italic),
           let font = NSFont(descriptor: descriptor, size: base.pointSize) {
            return font
        }
        var result = base
        if traits.contains(.bold) {
            result = RichTextMarkApplier.synthesizedFont(result, adding: .bold)
        }
        if traits.contains(.italic) {
            result = RichTextMarkApplier.synthesizedFont(result, adding: .italic)
        }
        return result
    }
}
