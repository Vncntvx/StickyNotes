import Testing
import Foundation
import Domain

// MARK: - FontPreference tests (T147 / T163q)
//
// Per tasks.md T147/T163q: "Domain test: FontPreference persistence +
// Chinese/English fallback selection for unsupported glyphs per FR-043".
//
// Verifies:
// - Codable round-trip (persistence through App Group UserDefaults JSON).
// - CJK text selects the fallback family; Latin text selects the primary.
// - Mixed Chinese-English text selects the fallback (needed for the CJK
//   glyphs).
// - System default has both families set.
// - No glyph support probing in Domain (the App layer handles it) — the
//   selection rule is deterministic.

@Suite struct FontPreferenceTests {

    @Test
    func codableRoundTripPreservesBothFamilies() throws {
        let preference = FontPreference(primaryFamily: "Avenir Next", fallbackFamily: "Songti SC")
        let data = try JSONEncoder().encode(preference)
        let decoded = try JSONDecoder().decode(FontPreference.self, from: data)
        #expect(decoded == preference)
    }

    @Test
    func latinTextUsesPrimaryFamily() {
        let preference = FontPreference(primaryFamily: "Helvetica", fallbackFamily: "PingFang SC")
        #expect(preference.family(for: "Hello world 123!") == "Helvetica")
        #expect(preference.family(for: "café naïve") == "Helvetica")
    }

    @Test
    func cjkTextUsesFallbackFamily() {
        let preference = FontPreference(primaryFamily: "Helvetica", fallbackFamily: "PingFang SC")
        #expect(preference.family(for: "你好世界") == "PingFang SC")
        #expect(preference.family(for: "混合 Chinese text") == "PingFang SC")
        #expect(preference.family(for: "日本語") == "PingFang SC")
        #expect(preference.family(for: "한국어") == "PingFang SC")
    }

    @Test
    func nilFamiliesFallBackToSystemDefault() {
        let preference = FontPreference()
        #expect(preference.family(for: "Latin") == FontPreference.systemDefault.primaryFamily)
        #expect(preference.family(for: "中文") == FontPreference.systemDefault.fallbackFamily)
        #expect(preference.primaryFamily == nil)
        #expect(preference.fallbackFamily == nil)
    }

    @Test
    func systemDefaultHasBothFamilies() {
        #expect(FontPreference.systemDefault.primaryFamily != nil)
        #expect(FontPreference.systemDefault.fallbackFamily != nil)
    }

    @Test
    func cjkDetectionCoversCjkUnifiedIdeographs() {
        #expect(FontPreference.containsCJK("你好"))
        #expect(FontPreference.containsCJK("。"))
        #expect(!FontPreference.containsCJK("a"))
        #expect(!FontPreference.containsCJK("Hello"))
        #expect(!FontPreference.containsCJK(""))
        #expect(!FontPreference.containsCJK("123 !?@"))
    }
}
