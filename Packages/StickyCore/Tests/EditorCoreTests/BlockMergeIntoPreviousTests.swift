import Testing
import Foundation
import Domain
@testable import EditorCore

// MARK: - Merge-into-previous block tests (2026-08-14)
//
// 块首 Backspace 的"并入上一块"纯函数：非空块（todo/code/正文）的文本接到
// 上一块末尾，块本身移除。语义：
// - 首块 / 越界 / 上一块是特殊块（无法承载文本）→ 不可合并（nil）；
// - 富文本上一块：runs/paragraphs 偏移平移，marks/link/hardBreak 保留；
// - todo/code 上一块：文本拼接，todoId/language 保留；
// - 空文本本块：仅移除（无文本融合，与 FR-050a 一致）；
// - 上一块身份（id/sortKey/noteId）保留。

@Suite struct BlockMergeIntoPreviousTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000002")!

    private func richBlock(
        _ text: String,
        sortKey: Int,
        runs: [RichTextRun] = []
    ) -> Block {
        let scalars = Array(text.unicodeScalars)
        let paragraph = RichTextParagraph(
            startScalar: 0,
            endScalar: scalars.count,
            style: .body,
            runs: runs
        )
        return Block(
            noteId: Self.noteId,
            kind: .richText,
            sortKey: sortKey,
            payload: .richText(RichTextDocument(text: text, paragraphs: [paragraph])),
            lastModifiedDeviceId: Self.deviceId
        )
    }

    private func todoBlock(
        _ text: String,
        sortKey: Int,
        todoId: UUID = UUID(),
        runs: [RichTextRun] = []
    ) -> Block {
        let scalars = Array(text.unicodeScalars)
        let paragraph = RichTextParagraph(
            startScalar: 0,
            endScalar: scalars.count,
            style: .body,
            runs: runs
        )
        return Block(
            noteId: Self.noteId,
            kind: .todo,
            sortKey: sortKey,
            payload: .todo(TodoPayload(
                todoId: todoId,
                richText: RichTextDocument(text: text, paragraphs: [paragraph])
            )),
            lastModifiedDeviceId: Self.deviceId
        )
    }

    private func codeBlock(
        _ text: String,
        sortKey: Int,
        language: String? = nil
    ) -> Block {
        Block(
            noteId: Self.noteId,
            kind: .code,
            sortKey: sortKey,
            payload: .code(CodePayload(text: text, language: language)),
            lastModifiedDeviceId: Self.deviceId
        )
    }

    private func fileRefBlock(sortKey: Int) -> Block {
        Block(
            noteId: Self.noteId,
            kind: .fileRef,
            sortKey: sortKey,
            payload: .fileReference(FileReferencePayload(
                displayName: "ref.pdf",
                contentType: "application/pdf",
                approximateSize: 10,
                originDeviceId: Self.deviceId,
                addedAt: Date()
            )),
            lastModifiedDeviceId: Self.deviceId
        )
    }

    private static let noteId = UUID()

    // MARK: - Guards

    @Test
    func firstBlockCannotMergeIntoNothing() {
        let blocks = [richBlock("only", sortKey: 0)]
        #expect(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: 0) == nil,
                "the first block has no predecessor")
    }

    @Test
    func outOfBoundsIndexIsNoOp() {
        let blocks = [richBlock("one", sortKey: 0), richBlock("two", sortKey: 1024)]
        #expect(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: 2) == nil)
        #expect(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: -1) == nil)
    }

    @Test
    func specialBlockPredecessorCannotAcceptText() {
        let blocks = [
            fileRefBlock(sortKey: 0),
            richBlock("body", sortKey: 1024),
        ]
        #expect(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: 1) == nil,
                "a file-reference block cannot receive text")
    }

    // MARK: - richText predecessor

    @Test
    func richTextAppendsIntoPreviousRichText() {
        let blocks = [
            richBlock("Hello ", sortKey: 0),
            richBlock("world", sortKey: 1024),
        ]
        let merged = try! #require(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: 1))
        #expect(merged.count == 1)
        guard case .richText(let doc) = merged[0].payload else {
            Issue.record("expected a rich-text payload"); return
        }
        #expect(doc.text == "Hello world", "the current block's text appends to the previous")
    }

    @Test
    func runsShiftByPreviousScalarCount() {
        // "中文" is 2 scalars — the offset must be scalar-based, not UTF-16.
        let prevRuns = [RichTextRun(startScalar: 0, endScalar: 2, marks: [.bold])]
        let currentRuns = [RichTextRun(startScalar: 0, endScalar: 5, marks: [.italic, .underline], link: URL(string: "https://example.com")?.absoluteString)]
        let blocks = [
            richBlock("中文", sortKey: 0, runs: prevRuns),
            richBlock("hello", sortKey: 1024, runs: currentRuns),
        ]
        let merged = try! #require(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: 1))
        guard case .richText(let doc) = merged[0].payload else {
            Issue.record("expected a rich-text payload"); return
        }
        #expect(doc.text == "中文hello")
        let runs = doc.paragraphs.flatMap(\.runs).sorted { $0.startScalar < $1.startScalar }
        #expect(runs.count == 2)
        let shifted = runs[1]
        #expect(shifted.startScalar == 2, "current runs shift by the previous scalar count")
        #expect(shifted.endScalar == 7)
        #expect(shifted.marks == [.italic, .underline], "marks survive the merge")
        #expect(shifted.link == "https://example.com", "link survives the merge")
        #expect(runs[0].marks == [.bold], "previous runs are untouched")
    }

    @Test
    func paragraphsShiftWithStylePreserved() {
        var doc = RichTextDocument.empty
        let scalarCount = "line2".unicodeScalars.count
        doc = RichTextDocument(
            text: "line2",
            paragraphs: [RichTextParagraph(startScalar: 0, endScalar: scalarCount, style: .bullet, runs: [])]
        )
        let blocks = [
            richBlock("line1\n", sortKey: 0),
            Block(
                noteId: Self.noteId,
                kind: .richText,
                sortKey: 1024,
                payload: .richText(doc),
                lastModifiedDeviceId: Self.deviceId
            ),
        ]
        let merged = try! #require(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: 1))
        guard case .richText(let mergedDoc) = merged[0].payload else {
            Issue.record("expected a rich-text payload"); return
        }
        #expect(mergedDoc.text == "line1\nline2")
        let paragraph = mergedDoc.paragraphs.last
        #expect(paragraph?.style == .bullet, "paragraph style survives the merge")
        #expect(paragraph?.startScalar == 6, "paragraph offsets shift by the previous length")
        #expect(paragraph?.endScalar == 11)
    }

    // MARK: - todo / code sources

    @Test
    func todoAppendsIntoPreviousRichText() {
        let blocks = [
            richBlock("Note: ", sortKey: 0),
            todoBlock("buy milk", sortKey: 1024),
        ]
        let merged = try! #require(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: 1))
        #expect(merged.count == 1)
        guard case .richText(let doc) = merged[0].payload else {
            Issue.record("expected a rich-text payload"); return
        }
        #expect(doc.text == "Note: buy milk", "todo text appends into the previous rich-text block")
    }

    @Test
    func codeAppendsIntoPreviousRichTextAsPlainText() {
        let blocks = [
            richBlock("echo ", sortKey: 0),
            codeBlock("hi", sortKey: 1024),
        ]
        let merged = try! #require(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: 1))
        guard case .richText(let doc) = merged[0].payload else {
            Issue.record("expected a rich-text payload"); return
        }
        #expect(doc.text == "echo hi", "code text appends as plain text (no runs)")
        #expect(doc.paragraphs.flatMap(\.runs).isEmpty)
    }

    // MARK: - todo predecessor

    @Test
    func richTextAppendsIntoPreviousTodoKeepingTodoId() {
        let todoId = UUID()
        let blocks = [
            todoBlock("task", sortKey: 0, todoId: todoId),
            richBlock(" detail", sortKey: 1024),
        ]
        let merged = try! #require(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: 1))
        #expect(merged.count == 1)
        guard case .todo(let payload) = merged[0].payload else {
            Issue.record("expected a todo payload"); return
        }
        #expect(payload.todoId == todoId, "the previous todo's identity survives")
        #expect(payload.richText.text == "task detail")
    }

    // MARK: - code predecessor

    @Test
    func codeAppendsIntoPreviousCodeKeepingLanguage() {
        let blocks = [
            codeBlock("let a = 1", sortKey: 0, language: "swift"),
            codeBlock("\nlet b = 2", sortKey: 1024),
        ]
        let merged = try! #require(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: 1))
        #expect(merged.count == 1)
        guard case .code(let payload) = merged[0].payload else {
            Issue.record("expected a code payload"); return
        }
        #expect(payload.text == "let a = 1\nlet b = 2")
        #expect(payload.language == "swift", "the previous code's language survives")
    }

    // MARK: - empty / identity

    @Test
    func emptyBlockRemovesWithoutTextFusion() {
        let blocks = [
            richBlock("keep", sortKey: 0),
            richBlock("", sortKey: 1024),
        ]
        let merged = try! #require(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: 1))
        #expect(merged.count == 1)
        guard case .richText(let doc) = merged[0].payload else {
            Issue.record("expected a rich-text payload"); return
        }
        #expect(doc.text == "keep", "an empty block is removed without text fusion")
    }

    @Test
    func mergedBlockKeepsPreviousIdentity() {
        let previous = richBlock("one", sortKey: 42)
        let blocks = [previous, richBlock("two", sortKey: 1066)]
        let merged = try! #require(BlockMergeOperation.mergingIntoPrevious(blocks: blocks, index: 1))
        #expect(merged[0].id == previous.id, "the merged block keeps the previous id")
        #expect(merged[0].sortKey == 42, "the merged block keeps the previous sortKey")
        #expect(merged[0].noteId == previous.noteId)
    }
}
