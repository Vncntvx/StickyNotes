import Testing
import Foundation
import AppKit
import Domain
@testable import StickyNotes

// MARK: - FR-043 font-preference application (T308)
//
// Per tasks.md T308: the stored global font preference MUST drive the
// editor's effective font families — primary (Latin) + fallback (CJK) —
// instead of always using `NSFont.systemFont(ofSize:)`. Unset preference
// keeps the system default. Written FIRST and must FAIL before the
// implementation (Constitution XII).

@Suite("FR-043 font preference application")
struct FontPreferenceApplicationTests {

    private static var suite: UserDefaults {
        UserDefaults.standard
    }

    private func resetPreference() {
        Self.suite.removeObject(forKey: FontPreferenceStore.key)
    }

    @Test func storedPreferenceDrivesPrimaryAndCJKFallbackFamilies() throws {
        resetPreference()
        FontPreferenceStore.save(FontPreference(
            primaryFamily: "Helvetica",
            fallbackFamily: "PingFang SC"
        ))

        let resolver = NoteFontResolver.load()
        let latin = resolver.font(size: 13, traits: [], for: "Hello world")
        let cjk = resolver.font(size: 13, traits: [], for: "中文测试")

        #expect(latin.familyName == "Helvetica")
        #expect(cjk.familyName == "PingFang SC")
        #expect(latin.pointSize == 13)
        #expect(cjk.pointSize == 13)
    }

    @Test func mixedLatinCJKTextSplitsIntoCoverageSegments() throws {
        resetPreference()
        FontPreferenceStore.save(FontPreference(
            primaryFamily: "Helvetica",
            fallbackFamily: "PingFang SC"
        ))

        let resolver = NoteFontResolver.load()
        let segments = resolver.segmentedFonts(text: "Hello 世界", size: 13, traits: [])
        let families = segments.map { ($0.segment, $0.font.familyName) }

        #expect(families.count == 2)
        #expect(families[0].0 == "Hello ")
        #expect(families[0].1 == "Helvetica")
        #expect(families[1].0 == "世界")
        #expect(families[1].1 == "PingFang SC")
    }

    @Test func unsetPreferenceKeepsSystemFont() throws {
        resetPreference()

        let resolver = NoteFontResolver.load()
        let system = NSFont.systemFont(ofSize: 13)
        #expect(resolver.font(size: 13, traits: [], for: "hello").familyName == system.familyName)
    }

    @Test func invalidFamilyFallsBackToSystemFont() throws {
        resetPreference()
        FontPreferenceStore.save(FontPreference(
            primaryFamily: "Definitely-Not-A-Real-Font-2026",
            fallbackFamily: "PingFang SC"
        ))

        let resolver = NoteFontResolver.load()
        let system = NSFont.systemFont(ofSize: 13)
        #expect(resolver.font(size: 13, traits: [], for: "hello").familyName == system.familyName)
    }

    // MARK: - 003 T042 (FR-055): single "note font" concept

    @Test func singleUserFacingNoteFontConcept() {
        // FR-055: ONE user-facing "note font" concept — primary family with
        // system fallback; no implementation typography terms ("English
        // font"/"Chinese font" are gone from the user surface).
        #expect(FontPreferenceUI.singleNoteFontConcept == true)
        #expect(FontPreferenceUI.usesImplementationTypographyTerms == false,
                "user surface must not expose implementation typography terms (FR-055)")
        #expect(FontPreferenceUI.systemFallbackProvided == true)
    }

    @Test func storageKeyUnchanged() {
        // FR-055: the storage key is unchanged (001 FR-043 behavior).
        #expect(FontPreferenceStore.key == "local.stickynotes.fontPreference")
    }

    @Test func bilingualPreviewMeaningful() {
        // FR-055 (Rev 3): a meaningful bilingual mixed-language preview
        // exists — multi-line so the Text Spacing effect is actually
        // visible (single-line text cannot preview line spacing).
        let sample = FontPreferenceUI.bilingualPreviewSample
        #expect(sample.split(separator: "\n").count >= 3,
                "preview must span at least three lines (Rev 3)")
        #expect(sample.contains("The quick brown fox"), "Latin sample line")
        let hasCJK = sample.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        #expect(hasCJK, "CJK sample line")
        #expect(FontPreferenceUI.bilingualPreviewEnabled == true)
    }
}
