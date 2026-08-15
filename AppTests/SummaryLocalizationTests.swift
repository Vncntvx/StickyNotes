import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - R3.6 summary localization tests (T024)
//
// Per remediation roadmap 2026-08-15 R3.6 (A-7 localize): the generated
// summary's screenshot/image placeholders must resolve through
// `String(localized:)` (the app bundle's Localizable.xcstrings), not a
// hard-coded English literal. Under zh-Hans the card title for a
// caption-less screenshot must read the localized text; the assertion is
// locale-agnostic — it compares the placeholder against the very
// localization call, so it fails in ANY locale that renders the two
// differently (pre-fix: hard-coded "Screenshot" != "屏幕截图").

@Suite struct SummaryLocalizationTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000009")!

    private func captionlessScreenshotBlocks() -> [Block] {
        [Block(
            noteId: UUID(),
            kind: .screenshot,
            sortKey: 0,
            payload: .screenshot(ScreenshotPayload(
                originalAssetId: UUID(), thumbnailAssetId: UUID(),
                caption: nil, capturedAt: Date()
            )),
            lastModifiedDeviceId: Self.deviceId
        )]
    }

    private func captionlessImageBlocks() -> [Block] {
        [Block(
            noteId: UUID(),
            kind: .image,
            sortKey: 0,
            payload: .image(EmbeddedImagePayload(
                originalAssetId: UUID(), thumbnailAssetId: UUID(),
                caption: nil
            )),
            lastModifiedDeviceId: Self.deviceId
        )]
    }

    @Test func screenshotPlaceholderResolvesThroughLocalization() {
        let summary = NoteSummary.generatedSummary(for: captionlessScreenshotBlocks())
        #expect(summary == String(localized: "Screenshot"),
                "caption-less screenshot summary must match the localized placeholder (R3.6/A-7)")
        let line = NoteSummary.firstMeaningfulLine(for: captionlessScreenshotBlocks())
        #expect(line == String(localized: "Screenshot"),
                "window-title line must use the same localized placeholder (R3.6/A-4)")
    }

    @Test func imagePlaceholderResolvesThroughLocalization() {
        let summary = NoteSummary.generatedSummary(for: captionlessImageBlocks())
        #expect(summary == String(localized: "Image"),
                "caption-less image summary must match the localized placeholder (R3.6/A-7)")
        let line = NoteSummary.firstMeaningfulLine(for: captionlessImageBlocks())
        #expect(line == String(localized: "Image"))
    }

    @Test func firstMeaningfulLineMatchesGeneratedSummaryForText() {
        // The single-source extraction (R3.6/A-4): the window-title line
        // variant and the clipped-summary variant agree on the FIRST
        // meaningful content when the first block is short text.
        let blocks = [
            Block(
                noteId: UUID(), kind: .richText, sortKey: 1,
                payload: .richText(.plain("second line")),
                lastModifiedDeviceId: Self.deviceId
            ),
            Block(
                noteId: UUID(), kind: .richText, sortKey: 0,
                payload: .richText(.plain("first line")),
                lastModifiedDeviceId: Self.deviceId
            ),
        ]
        #expect(NoteSummary.firstMeaningfulLine(for: blocks) == "first line")
        #expect(NoteSummary.generatedSummary(for: blocks) == "first line")
    }
}
