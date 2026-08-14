import Testing
import AppKit
import Domain
@testable import StickyNotes

// MARK: - 003 T182 (FR-055/055a Rev 3, 2026-08-14)

/// Tests for the Note body font choice presentation (system font-family
/// picker), the shared line-spacing value mapping, the multi-line preview
/// sample, and the card body preview font decision. The view consults these
/// pure types; the tests assert them (project pattern — SettingsPolicies).
struct NoteFontChoiceTests {

    // MARK: NoteFontChoicePresentation

    @Test func systemDefaultIsFirstOption() {
        let options = NoteFontChoicePresentation.options(families: ["Avenir", "Helvetica"], storedFamily: nil)
        #expect(options.first == NoteFontChoicePresentation.systemDefaultTitle)
        #expect(options.count == 3)
    }

    @Test func optionsAreSortedCaseInsensitively() {
        let options = NoteFontChoicePresentation.options(
            families: ["Zapfino", "american typewriter", "Avenir"],
            storedFamily: nil
        )
        let families = options.dropFirst()
        #expect(Array(families) == ["american typewriter", "Avenir", "Zapfino"],
                "families must be sorted case-insensitively after the System Default option")
    }

    @Test func storedFamilyMissingFromSystemListIsRetained() {
        // FR-055a: the selection binding must never dangle when the running
        // system no longer provides the stored family.
        let options = NoteFontChoicePresentation.options(
            families: ["Avenir", "Helvetica"],
            storedFamily: "Some Removed Font"
        )
        #expect(options.contains("Some Removed Font"))
    }

    @Test func storedFamilyPresentInListIsNotDuplicated() {
        let options = NoteFontChoicePresentation.options(
            families: ["Avenir", "Helvetica"],
            storedFamily: "Helvetica"
        )
        #expect(options.filter { $0 == "Helvetica" }.count == 1)
    }

    @Test func selectionMapsNilToSystemDefault() {
        #expect(NoteFontChoicePresentation.selectedOption(for: nil) == NoteFontChoicePresentation.systemDefaultTitle)
        #expect(NoteFontChoicePresentation.selectedOption(for: "Avenir") == "Avenir")
    }

    @Test func optionMapsBackToNilFamilyForSystemDefault() {
        #expect(NoteFontChoicePresentation.family(from: NoteFontChoicePresentation.systemDefaultTitle) == nil)
        #expect(NoteFontChoicePresentation.family(from: "Avenir") == "Avenir")
    }

    // MARK: TextSpacingPreset.lineSpacingValue (shared single source)

    @Test func lineSpacingValueMatchesEditorTypographyMapping() {
        // The values must stay identical to the pre-refactor
        // `EditorTypography.lineSpacing` mapping (Phase 5 prototype
        // constants — tuning is a visual acceptance, not a value contract).
        #expect(TextSpacingPreset.compact.lineSpacingValue == -1.5)
        #expect(TextSpacingPreset.standard.lineSpacingValue == nil)
        #expect(TextSpacingPreset.relaxed.lineSpacingValue == 4.0)
    }

    @Test func editorTypographyUsesSharedLineSpacingSource() {
        #expect(EditorTypography.system(textSize: 13).lineSpacing == TextSpacingPreset.standard.lineSpacingValue)
        let relaxed = EditorTypography(fontPreference: nil, textSpacing: .relaxed, textSize: 13)
        #expect(relaxed.lineSpacing == 4.0)
    }

    // MARK: FontPreferenceUI preview sample (FR-055 Rev 3)

    @Test func previewSampleIsMultilineAndBilingual() {
        // Rev 3: the preview must actually preview Text Spacing, which only
        // affects inter-line spacing — a single line cannot show it.
        #expect(FontPreferenceUI.bilingualPreviewSample.split(separator: "\n").count >= 3)
        #expect(FontPreferenceUI.bilingualPreviewSample.contains("The quick brown fox"))
        let hasCJK = FontPreferenceUI.bilingualPreviewSample.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value)
        }
        #expect(hasCJK, "the preview sample must mix Latin and CJK")
    }

    // MARK: CardBodyFont (FR-055 Rev 3)

    @Test func cardPreviewFollowsStoredPrimaryFamily() {
        let preference = FontPreference(primaryFamily: "Avenir Next", fallbackFamily: "PingFang SC")
        #expect(CardBodyFont.previewFamily(for: preference) == "Avenir Next")
        #expect(CardBodyFont.previewFamily(for: nil) == nil,
                "nil preference = system font — the card keeps the system caption font")
    }
}
