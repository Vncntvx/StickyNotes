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
        UserDefaults(suiteName: "group.local.stickynotes.placeholder")!
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
}
