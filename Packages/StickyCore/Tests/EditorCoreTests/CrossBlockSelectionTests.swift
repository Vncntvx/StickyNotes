import Testing
import Foundation
import Domain
@testable import EditorCore

// MARK: - Cross-block selection tests (T254, FR-054)
//
// Per tasks.md T254: "assert selection spans block boundaries (paragraph/
// list item/todo item/heading); copying places both plain-text and rich-text
// (RTF/HTML) representations with ONLY application-supported formatting
// (FR-053); deleting removes only the selected characters and an emptied
// block is merged away per FR-050a with a single Undo restoring; the
// trailing empty padding paragraph is never selectable".

@Suite struct CrossBlockSelectionTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    private func richBlock(_ text: String, noteId: UUID, sortKey: Int, runs: [RichTextRun] = []) -> Block {
        let scalars = Array(text.unicodeScalars)
        let paragraph = RichTextParagraph(
            startScalar: 0,
            endScalar: scalars.count,
            style: .body,
            runs: runs
        )
        return Block(
            noteId: noteId,
            kind: .richText,
            sortKey: sortKey,
            payload: .richText(RichTextDocument(text: text, paragraphs: [paragraph])),
            lastModifiedDeviceId: Self.deviceId
        )
    }

    @Test
    func selectionSpansBlockBoundaries() {
        let noteId = UUID()
        let blocks = [
            richBlock("Hello world", noteId: noteId, sortKey: 0),
            richBlock("Second block", noteId: noteId, sortKey: 1024),
            richBlock("Third", noteId: noteId, sortKey: 2048),
        ]
        let selection = CrossBlockSelection(selections: [
            (blockId: blocks[0].id, range: 0..<5),
            (blockId: blocks[1].id, range: 0..<6),
        ])
        let plain = CrossBlockSelectionCore.selectedPlainText(blocks: blocks, selection: selection)
        #expect(plain == "Hello\nSecond")
    }

    @Test
    func trailingPaddingParagraphIsNeverSelectable() {
        let noteId = UUID()
        let blocks = [
            richBlock("Content", noteId: noteId, sortKey: 0),
            richBlock("", noteId: noteId, sortKey: 1024),  // trailing padding
        ]
        #expect(CrossBlockSelectionCore.isTrailingPaddingParagraph(blocks: blocks, index: 1))

        // Even if the selection includes it, the padding paragraph
        // contributes nothing.
        let selection = CrossBlockSelection(selections: [
            (blockId: blocks[0].id, range: 0..<7),
            (blockId: blocks[1].id, range: 0..<1),
        ])
        let plain = CrossBlockSelectionCore.selectedPlainText(blocks: blocks, selection: selection)
        #expect(plain == "Content", "padding paragraph must never be selectable (FR-054)")
    }

    @Test
    func copyProducesPlainAndRichRepresentations() {
        let noteId = UUID()
        let doc = RichTextDocument(
            text: "Hello **bold**",
            paragraphs: [RichTextParagraph(
                startScalar: 0,
                endScalar: 15,
                style: .body,
                runs: [RichTextRun(startScalar: 6, endScalar: 12, marks: [.bold])]
            )]
        )
        let boldBlock = Block(
            noteId: noteId,
            kind: .richText,
            sortKey: 0,
            payload: .richText(doc),
            lastModifiedDeviceId: Self.deviceId
        )
        let blocks = [boldBlock]
        let selection = CrossBlockSelection(selections: [(blockId: blocks[0].id, range: 0..<15)])

        let plain = CrossBlockSelectionCore.selectedPlainText(blocks: blocks, selection: selection)
        #expect(plain == "Hello **bold**")

        let rtf = CrossBlockSelectionCore.richTextRepresentation(blocks: blocks, selection: selection)
        #expect(rtf.hasPrefix("{\\rtf1"))
        #expect(rtf.contains("\\b "), "bold mark must be encoded in RTF (FR-053)")
        // No unsupported formatting commands leak in.
        #expect(!rtf.contains("\\highlight"))
        #expect(!rtf.contains("\\fs"))
    }

    @Test
    func rtfEscapesSpecialCharacters() {
        let escaped = CrossBlockSelectionCore.escapeRTF("a {b} c\\d\n")
        #expect(escaped.contains("\\{"))
        #expect(escaped.contains("\\}"))
        #expect(escaped.contains("\\\\"))
        #expect(escaped.contains("\\line "))
    }

    @Test
    func deleteRemovesOnlySelectedCharacters() {
        let noteId = UUID()
        let blocks = [
            richBlock("Hello world", noteId: noteId, sortKey: 0),
            richBlock("Second block", noteId: noteId, sortKey: 1024),
        ]
        let selection = CrossBlockSelection(selections: [
            (blockId: blocks[0].id, range: 0..<5),   // remove "Hello"
        ])
        let updated = CrossBlockSelectionCore.deletingSelection(
            blocks: blocks,
            selection: selection,
            noteId: noteId,
            deviceId: Self.deviceId
        )
        #expect(updated.count == 2)
        if case .richText(let doc) = updated[0].payload {
            #expect(doc.text == " world", "only the selected characters are removed")
        } else {
            Issue.record("expected rich text")
        }
    }

    @Test
    func blockTextHelperReturnsCanonicalTextPerKind() {
        let noteId = UUID()
        let code = Block(noteId: noteId, kind: .code, sortKey: 0,
                         payload: .code(CodePayload(text: "let a = 1")),
                         lastModifiedDeviceId: Self.deviceId)
        #expect(CrossBlockSelectionCore.blockText(code) == "let a = 1")
    }
}
