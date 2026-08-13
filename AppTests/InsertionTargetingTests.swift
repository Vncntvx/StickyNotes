import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - Insertion-targeting tests (004 T007, spec FR-010/Q4)
//
// Per tasks.md T007 and contracts §5: `resolveInsertionTarget`
// (caretSplit / afterBlock / append) and `splitRichTextBlock` (run
// attributes and marks preserved; paragraphs re-derived per side).

@MainActor
@Suite struct InsertionTargetingTests {

    private let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000021")!

    private func block(
        id: UUID,
        kind: BlockKind,
        sortKey: Int,
        payload: CanonicalBlockPayload
    ) -> Block {
        Block(
            id: id,
            noteId: UUID(),
            kind: kind,
            sortKey: sortKey,
            payload: payload,
            lastModifiedDeviceId: deviceId
        )
    }

    // MARK: resolveInsertionTarget

    @Test
    func caretInRichTextResolvesToCaretSplit() {
        let richId = UUID()
        let blocks = [
            block(id: richId, kind: .richText, sortKey: 0, payload: .richText(.plain("hello world"))),
            block(id: UUID(), kind: .todo, sortKey: 1024, payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("x"))))
        ]
        let target = NoteWindowDerivations.resolveInsertionTarget(
            blocks: blocks,
            context: InsertionContext(caretBlockId: richId, caretOffset: 5)
        )
        #expect(target == .caretSplit(blockId: richId, offset: 5), "caret in richText → split at caret (FR-010)")
    }

    @Test
    func caretInUnknownBlockDegradesToAppend() {
        let blocks = [
            block(id: UUID(), kind: .richText, sortKey: 0, payload: .richText(.plain("hello")))
        ]
        let target = NoteWindowDerivations.resolveInsertionTarget(
            blocks: blocks,
            context: InsertionContext(caretBlockId: UUID(), caretOffset: 2)
        )
        #expect(target == .append, "stale caret context → append (contracts §5)")
    }

    @Test
    func focusedSpecialBlockResolvesToAfterBlock() {
        let todoId = UUID()
        let blocks = [
            block(id: UUID(), kind: .richText, sortKey: 0, payload: .richText(.plain("hello"))),
            block(id: todoId, kind: .todo, sortKey: 1024, payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("x"))))
        ]
        let target = NoteWindowDerivations.resolveInsertionTarget(
            blocks: blocks,
            context: InsertionContext(focusedSpecialBlockId: todoId)
        )
        #expect(target == .afterBlock(blockId: todoId), "focused special block → insert after it (FR-010)")
    }

    @Test
    func noContextResolvesToAppend() {
        let blocks = [
            block(id: UUID(), kind: .richText, sortKey: 0, payload: .richText(.plain("hello")))
        ]
        #expect(NoteWindowDerivations.resolveInsertionTarget(blocks: blocks, context: InsertionContext()) == .append,
                "no active insertion point → append (FR-010)")
    }

    @Test
    func richTextCaretBeatsSpecialBlockFocus() {
        let richId = UUID()
        let todoId = UUID()
        let blocks = [
            block(id: richId, kind: .richText, sortKey: 0, payload: .richText(.plain("hello"))),
            block(id: todoId, kind: .todo, sortKey: 1024, payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("x"))))
        ]
        let target = NoteWindowDerivations.resolveInsertionTarget(
            blocks: blocks,
            context: InsertionContext(caretBlockId: richId, caretOffset: 1, focusedSpecialBlockId: todoId)
        )
        #expect(target == .caretSplit(blockId: richId, offset: 1), "caret context wins (FR-010)")
    }

    // MARK: splitRichTextBlock

    @Test
    func splitPreservesRunMarksOnBothSides() {
        let doc = RichTextDocument(
            text: "Hello bold world",
            paragraphs: [
                RichTextParagraph(
                    startScalar: 0,
                    endScalar: 16,
                    style: .body,
                    runs: [RichTextRun(startScalar: 6, endScalar: 10, marks: [.bold])]
                )
            ]
        )
        let (leading, trailing) = NoteWindowDerivations.splitRichTextBlock(payload: doc, offset: 8)
        #expect(leading.text == "Hello bo")
        #expect(trailing.text == "ld world")
        // The crossing bold run is split: [6,8) on the leading side, [0,2) on
        // the trailing side — marks preserved on both.
        let leadingBold = leading.paragraphs.flatMap(\.runs).filter { $0.marks.contains(.bold) }
        let trailingBold = trailing.paragraphs.flatMap(\.runs).filter { $0.marks.contains(.bold) }
        #expect(leadingBold == [RichTextRun(startScalar: 6, endScalar: 8, marks: [.bold])],
                "leading side keeps the bold run segment")
        #expect(trailingBold == [RichTextRun(startScalar: 0, endScalar: 2, marks: [.bold])],
                "trailing side keeps the bold run segment, re-based to 0")
    }

    @Test
    func splitKeepsMultipleMarksAndLink() {
        let doc = RichTextDocument(
            text: "a b c",
            paragraphs: [
                RichTextParagraph(
                    startScalar: 0,
                    endScalar: 5,
                    style: .body,
                    runs: [
                        RichTextRun(startScalar: 0, endScalar: 1, marks: [.bold, .underline], link: "https://example.com"),
                        RichTextRun(startScalar: 2, endScalar: 3, marks: [.italic, .strikethrough, .inlineCode])
                    ]
                )
            ]
        )
        let (leading, trailing) = NoteWindowDerivations.splitRichTextBlock(payload: doc, offset: 3)
        #expect(leading.text == "a b")
        #expect(trailing.text == " c")
        let leadingRuns = leading.paragraphs.flatMap(\.runs)
        let trailingRuns = trailing.paragraphs.flatMap(\.runs)
        #expect(leadingRuns.contains(RichTextRun(startScalar: 0, endScalar: 1, marks: [.bold, .underline], link: "https://example.com")))
        #expect(leadingRuns.contains(RichTextRun(startScalar: 2, endScalar: 3, marks: [.italic, .strikethrough, .inlineCode])),
                "the run ending exactly at the split stays in the leading block (no empty runs)")
        #expect(trailingRuns.isEmpty, "the trailing side is plain — the split consumed no marked text")
    }

    @Test
    func splitAtZeroAndAtEndAreDegenerate() {
        let doc = RichTextDocument.plain("hello")
        let (atZero) = NoteWindowDerivations.splitRichTextBlock(payload: doc, offset: 0)
        let (atEnd) = NoteWindowDerivations.splitRichTextBlock(payload: doc, offset: 5)
        #expect(atZero.leading.text == "")
        #expect(atZero.trailing.text == "hello")
        #expect(atEnd.leading.text == "hello")
        #expect(atEnd.trailing.text == "")
    }

    @Test
    func splitClampsOutOfBoundsOffsets() {
        let doc = RichTextDocument.plain("hello")
        let (leading, trailing) = NoteWindowDerivations.splitRichTextBlock(payload: doc, offset: 99)
        #expect(leading.text == "hello")
        #expect(trailing.text == "")
    }

    // MARK: UTF-16 → scalar caret offsets (004 修复：光标偏移单位)

    @Test
    func utf16CaretOffsetConvertsToScalarOffset() {
        // NSTextView 的 selectedRange.location 是 UTF-16 码元偏移；
        // canonical 文档与 splitRichTextBlock 使用 Unicode scalar 偏移。
        #expect(NoteWindowDerivations.scalarOffset(fromUTF16: 1, in: "你好") == 1)
        #expect(NoteWindowDerivations.scalarOffset(fromUTF16: 2, in: "你好") == 2)
        // "a😀b"：emoji 占 2 个 UTF-16 码元、1 个 scalar。
        #expect(NoteWindowDerivations.scalarOffset(fromUTF16: 3, in: "a😀b") == 2,
                "emoji caret offsets must count scalars, not UTF-16 units")
        #expect(NoteWindowDerivations.scalarOffset(fromUTF16: 4, in: "a😀b") == 3)
        #expect(NoteWindowDerivations.scalarOffset(fromUTF16: 0, in: "abc") == 0)
        #expect(NoteWindowDerivations.scalarOffset(fromUTF16: 99, in: "abc") == 3,
                "out-of-bounds offsets clamp to the document length")
    }

    @Test
    func utf16ScalarConversionFeedsCaretSplitCorrectly() {
        // CJK 光标拆分：UTF-16 偏移必须先转 scalar 才能正确落位。
        let doc = RichTextDocument.plain("你好世界")
        let scalar = NoteWindowDerivations.scalarOffset(fromUTF16: 2, in: doc.text)
        let (leading, trailing) = NoteWindowDerivations.splitRichTextBlock(payload: doc, offset: scalar)
        #expect(leading.text == "你好")
        #expect(trailing.text == "世界")
    }

    // MARK: trimmingTrailingEmptyLines (004 修复: caret-at-end consumes
    // the empty paragraph instead of spawning an empty trailing block)

    @Test
    func trimmingTrailingEmptyLinesStripsOnlyTheTrailingParagraphs() {
        #expect(NoteWindowDerivations.trimmingTrailingEmptyLines(.plain("abc\n")).text == "abc")
        #expect(NoteWindowDerivations.trimmingTrailingEmptyLines(.plain("abc\n\n\n")).text == "abc")
        #expect(NoteWindowDerivations.trimmingTrailingEmptyLines(.plain("abc")).text == "abc",
                "no trailing newline → unchanged")
        #expect(NoteWindowDerivations.trimmingTrailingEmptyLines(.plain("abc\n\ndef\n")).text == "abc\n\ndef",
                "interior empty lines are content")
        #expect(NoteWindowDerivations.trimmingTrailingEmptyLines(.plain("abc\n  \n")).text == "abc",
                "whitespace-only trailing paragraphs count as empty")
        #expect(NoteWindowDerivations.trimmingTrailingEmptyLines(.plain("")).text == "")
        #expect(NoteWindowDerivations.trimmingTrailingEmptyLines(.plain("\n\n")).text == "",
                "an all-empty-paragraph document trims to empty")
    }

    @Test
    func trimmingTrailingEmptyLinesPreservesRunsOnRemainingText() {
        let doc = RichTextDocument(
            text: "ab\n",
            paragraphs: [
                RichTextParagraph(
                    startScalar: 0, endScalar: 2, style: .body,
                    runs: [RichTextRun(startScalar: 0, endScalar: 2, marks: [.bold])]
                )
            ]
        )
        let trimmed = NoteWindowDerivations.trimmingTrailingEmptyLines(doc)
        #expect(trimmed.text == "ab")
        #expect(trimmed.paragraphs.flatMap(\.runs) == [RichTextRun(startScalar: 0, endScalar: 2, marks: [.bold])],
                "runs survive the trim")
    }

    @Test
    func splitAcrossParagraphBoundariesRebuildsParagraphs() {
        let doc = RichTextDocument(
            text: "line1\nline2",
            paragraphs: [
                RichTextParagraph(startScalar: 0, endScalar: 5, style: .body, runs: []),
                RichTextParagraph(startScalar: 6, endScalar: 11, style: .body, runs: [RichTextRun(startScalar: 6, endScalar: 11, marks: [.italic])])
            ]
        )
        let (leading, trailing) = NoteWindowDerivations.splitRichTextBlock(payload: doc, offset: 8)
        #expect(leading.text == "line1\nli")
        #expect(trailing.text == "ne2")
        let trailingRuns = trailing.paragraphs.flatMap(\.runs)
        #expect(trailingRuns == [RichTextRun(startScalar: 0, endScalar: 3, marks: [.italic])],
                "the italic run re-bases to the trailing document")
    }
}
