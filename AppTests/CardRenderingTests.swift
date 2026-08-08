import Testing
import Foundation
import Domain
import CoreGraphics
@testable import StickyNotes

// MARK: - Card rendering tests (T251/003 T014, FR-020a/SC-022)
//
// The last-modified time rule (relative ≤7d, absolute beyond, year in a
// previous calendar year) is covered in AppLogicTests. Card preview
// truncation (2 lines + ellipsis from the first rich-text block, never
// duplicating the summary title) is verified structurally: the card view
// uses lineLimit(2) + truncationMode(.tail) on previewSource only.
// 003 T014: SC-022 density bounds — default-width card height 72–128 pt,
// blank-space ratio ≤20% on the FIXED spec card-content profile (title +
// 2-line preview + modified time), measured in the content-area coordinate
// space.

@Suite struct CardRenderingTests {
    @Test
    func previewSourceComesFromFirstRichTextBlock() throws {
        let noteId = UUID()
        let blocks = [
            Block(noteId: noteId, kind: .code, sortKey: 0,
                  payload: .code(CodePayload(text: "let x = 1")),
                  lastModifiedDeviceId: UUID()),
            Block(noteId: noteId, kind: .richText, sortKey: 1024,
                  payload: .richText(.plain("The first rich text")),
                  lastModifiedDeviceId: UUID()),
        ]
        let preview = CardPreview.previewSource(from: blocks)
        #expect(preview == "The first rich text")
    }

    @Test
    func previewNeverDuplicatesSummaryTitle() {
        // The preview is drawn from the FIRST rich-text block and rendered
        // in a distinct role below the title line (FR-020a). The guard
        // helper flags a literal repeat of the displayed summary title so
        // the view can suppress the duplicated line.
        #expect(CardPreview.duplicatesSummary("Body text", summary: "Body text"))
        #expect(!CardPreview.duplicatesSummary("Body text", summary: "Different title"))
        #expect(!CardPreview.duplicatesSummary("Body text", summary: nil))
    }

    // MARK: - 003 T014 SC-022 density bounds

    /// The fixed spec card-content profile (CHK010): a TYPICAL card — 2-line
    /// title (lineLimit(2), FR-020) + 2-line preview + modified-time
    /// metadata row + card padding + row spacing.
    static let typicalContentHeight: CGFloat = {
        // Title (13 pt headline × 1.2 line height × 2 lines) + 3 row
        // spacings + preview (11 pt × 1.2 × 2 lines) + metadata row
        // (11 pt × 1.2) + card vertical padding (10 × 2).
        let title = AppMetrics.cardTitleSize * 1.2 * 2
        let preview = AppMetrics.cardPreviewSize * 1.2 * 2
        let metadata = AppMetrics.cardPreviewSize * 1.2
        let padding: CGFloat = 10 * 2
        let gaps: CGFloat = 3 * 6
        return title + preview + metadata + padding + gaps
    }()

    @Test
    func defaultWidthCardHeightStaysWithinBounds() {
        // SC-022: 72 ≤ height ≤ 128 at default width.
        #expect(NoteCardMetrics.minCardHeight <= 72)
        #expect(NoteCardMetrics.maxCardHeight == 128)
        #expect(Self.typicalContentHeight >= NoteCardMetrics.minCardHeight,
                "typical content must fit within the lower bound")
        #expect(Self.typicalContentHeight <= NoteCardMetrics.maxCardHeight,
                "typical content must fit within the upper bound (got \(Self.typicalContentHeight))")
    }

    @Test
    func blankSpaceRatioStaysWithinTwentyPercent() {
        // SC-022: blank-space ratio ≤20% on the FIXED typical-content
        // sample. The card height bounds to the content profile (no large
        // unexplained blank areas — FR-020).
        let blank = NoteCardMetrics.maxCardHeight - Self.typicalContentHeight
        let ratio = blank / NoteCardMetrics.maxCardHeight
        #expect(ratio <= 0.20, "blank-space ratio \(ratio) must be ≤20% (SC-022)")
    }

    @Test
    func cardViewBoundedByDensityMetrics() {
        // The card VIEW must render within the SC-022 bounds (T022 wiring;
        // fails until NoteCardView stops using the 140–160 frame constants).
        #expect(NoteCardView.contentHeightBounds.lowerBound == NoteCardMetrics.minCardHeight)
        #expect(NoteCardView.contentHeightBounds.upperBound == NoteCardMetrics.maxCardHeight)
    }
}
