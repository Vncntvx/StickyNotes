import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - Card rendering tests (T251, FR-020a)
//
// The last-modified time rule (relative ≤7d, absolute beyond, year in a
// previous calendar year) is covered in AppLogicTests. Card preview
// truncation (2 lines + ellipsis from the first rich-text block, never
// duplicating the summary title) is verified structurally: the card view
// uses lineLimit(2) + truncationMode(.tail) on previewSource only.
// File exists for task→file traceability.

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
}
