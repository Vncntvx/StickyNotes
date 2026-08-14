import Testing
import Foundation
import Observation
import Domain
@testable import StickyNotes

// MARK: - Typography preference state tests (Phase 2, 2026-08-14)
//
// The single observable typography source: persistence round trips for both
// preference keys, the read-time fallbacks, the nil-font-preference
// semantics (nil = macOS system font — NOT FontPreference.systemDefault),
// the observation contract SwiftUI relies on for live updates, and the
// prototype spacing mapping (standard writes no paragraph style).

@MainActor
@Suite struct TypographyPreferencesTests {

    @Test
    func standardIsDefaultWhenNothingStored() {
        TextSpacingPreferenceStore.clear()
        defer { TextSpacingPreferenceStore.clear() }
        #expect(TextSpacingPreferenceStore.load() == .standard,
                "no stored value must resolve to the standard preset")
    }

    @Test
    func spacingStoreRoundTripsAllPresets() {
        TextSpacingPreferenceStore.clear()
        defer { TextSpacingPreferenceStore.clear() }
        for preset in TextSpacingPreset.allCases {
            TextSpacingPreferenceStore.save(preset)
            #expect(TextSpacingPreferenceStore.load() == preset)
        }
    }

    @Test
    func spacingStoreFallsBackToStandardOnUnrecognizedValue() {
        UserDefaults.standard.set("extra-relaxed", forKey: TextSpacingPreferenceStore.key)
        defer { TextSpacingPreferenceStore.clear() }
        #expect(TextSpacingPreferenceStore.load() == .standard,
                "an unrecognized raw value degrades to standard (read-time fallback, no migration)")
    }

    @Test
    func nilFontPreferenceMeansSystemFontNotAppDefault() {
        // nil and FontPreference.systemDefault are DIFFERENT states — the
        // former renders NSFont.systemFont, the latter an explicit family.
        let system = EditorTypography(fontPreference: nil, textSpacing: .standard, textSize: 13)
        let explicit = EditorTypography(fontPreference: .systemDefault, textSpacing: .standard, textSize: 13)
        #expect(system != explicit,
                "nil preference must not collapse into the app-default families (Reset semantics)")
        #expect(system.fontPreference == nil)
        #expect(explicit.fontPreference == .systemDefault)
    }

    @Test
    func setFontPreferencePersistsAndClearResets() {
        FontPreferenceStore.clear()
        defer { FontPreferenceStore.clear() }
        let prefs = TypographyPreferences()
        prefs.setFontPreference(.systemDefault)
        #expect(FontPreferenceStore.load() == .systemDefault,
                "setFontPreference persists through FontPreferenceStore")
        #expect(prefs.fontPreference == .systemDefault)
        prefs.setFontPreference(nil)
        #expect(FontPreferenceStore.load() == nil,
                "Reset clears the stored key — the editor falls back to the system font")
        #expect(prefs.fontPreference == nil)
    }

    @Test
    func setTextSpacingPersists() {
        TextSpacingPreferenceStore.clear()
        defer { TextSpacingPreferenceStore.clear() }
        let prefs = TypographyPreferences()
        prefs.setTextSpacing(.relaxed)
        #expect(TextSpacingPreferenceStore.load() == .relaxed)
        #expect(prefs.textSpacing == .relaxed)
    }

    @Test
    func loadComposesBothPersistedPreferences() {
        FontPreferenceStore.clear()
        TextSpacingPreferenceStore.clear()
        defer {
            FontPreferenceStore.clear()
            TextSpacingPreferenceStore.clear()
        }
        FontPreferenceStore.save(.systemDefault)
        TextSpacingPreferenceStore.save(.compact)
        let prefs = TypographyPreferences.load()
        #expect(prefs.fontPreference == .systemDefault)
        #expect(prefs.textSpacing == .compact)
    }

    @Test
    func observableChangePropagatesToObservationTracking() async throws {
        final class FlagBox: @unchecked Sendable {
            var value = false
        }
        let prefs = TypographyPreferences()
        let textSpacingObserved = FlagBox()
        let fontObserved = FlagBox()
        withObservationTracking {
            _ = prefs.textSpacing
        } onChange: {
            textSpacingObserved.value = true
        }
        withObservationTracking {
            _ = prefs.fontPreference
        } onChange: {
            fontObserved.value = true
        }
        prefs.setTextSpacing(.relaxed)
        prefs.setFontPreference(.systemDefault)
        // onChange fires at the end of the transaction — give the runloop
        // a bounded window.
        for _ in 0..<50 where !(textSpacingObserved.value && fontObserved.value) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        defer {
            TextSpacingPreferenceStore.clear()
            FontPreferenceStore.clear()
        }
        #expect(textSpacingObserved.value, "@Observable must propagate textSpacing changes (live-update contract)")
        #expect(fontObserved.value, "@Observable must propagate fontPreference changes (live-update contract)")
    }

    @Test
    func lineSpacingPrototypeMapping() {
        let compact = EditorTypography(fontPreference: nil, textSpacing: .compact, textSize: 13)
        let standard = EditorTypography(fontPreference: nil, textSpacing: .standard, textSize: 13)
        let relaxed = EditorTypography(fontPreference: nil, textSpacing: .relaxed, textSize: 13)
        #expect(standard.lineSpacing == nil,
                "standard writes no paragraph style (zero delta from today's metrics)")
        guard let compactValue = compact.lineSpacing, let relaxedValue = relaxed.lineSpacing else {
            Issue.record("compact/relaxed must produce a line spacing value")
            return
        }
        #expect(compactValue < 0 && relaxedValue > 0 && compactValue < relaxedValue,
                "the three presets must be distinct (values are visual-tuning prototypes)")
    }
}
