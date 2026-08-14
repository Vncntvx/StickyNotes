import Foundation
import Domain

// MARK: - Merge-into-previous (2026-08-14)
//
// 块首 Backspace 的"并入上一块"核心：非空块（todo/code/正文）的文本接到
// 上一块末尾，块本身移除。与 FR-050a（并入后继、空块槽塌缩）正交——这是
// 用户显式的按键合并，只融合文本、不搬槽位。
//
// 规则：
// - 首块 / 越界 / 上一块是特殊块（fileRef/image/screenshot，无法承载
//   文本）→ 不可合并（nil）；
// - 富文本上一块：本块 runs/paragraphs 偏移平移（scalar），marks/link/
//   hardBreak/style 保留；code 文本以 plain 段接入（无 runs）；
// - todo 上一块：richText 文本拼接，todoId 保留；code 文本以 plain 接入；
// - code 上一块：纯文本拼接，language 保留（richText/todo 的 marks 在
//   plain 容器中自然丢失）；
// - 空文本本块：仅移除（无文本融合，与 FR-050a 一致）；
// - 上一块身份（id/sortKey/noteId/版本字段）保留。
//
// 本块为 todo 时其 TodoItem 行由 App 层级联删除（此处只返回块列表）。

extension BlockMergeOperation {

    /// Merges the block at `index` into its predecessor. Returns the updated
    /// block list (predecessor carries the fused text, `index` removed), or
    /// `nil` when the merge is not possible (no predecessor / special-block
    /// predecessor / out of bounds).
    public static func mergingIntoPrevious(
        blocks: [Block],
        index: Int
    ) -> [Block]? {
        guard index > 0, blocks.indices.contains(index) else { return nil }
        let current = blocks[index]
        let previous = blocks[index - 1]

        // An empty block carries no text to fuse — removal only (FR-050a
        // sibling behavior). The empty-block key path (with its own focus/
        // undo rules) stays separate; this function just does the slot math.
        if isEmpty(current) {
            var updated = blocks
            updated.remove(at: index)
            return updated
        }

        guard let mergedPayload = fusedPayload(previous: previous.payload, current: current.payload) else {
            // The predecessor cannot carry text (fileRef/image/screenshot).
            return nil
        }

        var updated = blocks
        updated[index - 1] = Block(
            id: previous.id,
            noteId: previous.noteId,
            kind: previous.kind,
            sortKey: previous.sortKey,
            payload: mergedPayload,
            versionId: previous.versionId,
            parentVersionId: previous.parentVersionId,
            lastModifiedDeviceId: previous.lastModifiedDeviceId,
            createdAt: previous.createdAt,
            modifiedAt: Date()
        )
        updated.remove(at: index)
        return updated
    }

    // MARK: - Payload fusion

    private static func fusedPayload(
        previous: CanonicalBlockPayload,
        current: CanonicalBlockPayload
    ) -> CanonicalBlockPayload? {
        switch (previous, current) {
        case (.richText(let prevDoc), .richText(let doc)):
            return .richText(fusedDocument(prevDoc, appending: doc))
        case (.richText(let prevDoc), .todo(let payload)):
            return .richText(fusedDocument(prevDoc, appending: payload.richText))
        case (.richText(let prevDoc), .code(let payload)):
            return .richText(fusedDocument(prevDoc, appendingPlain: payload.text))

        case (.todo(let prevPayload), .richText(let doc)):
            return .todo(TodoPayload(
                todoId: prevPayload.todoId,
                richText: fusedDocument(prevPayload.richText, appending: doc)
            ))
        case (.todo(let prevPayload), .todo(let payload)):
            return .todo(TodoPayload(
                todoId: prevPayload.todoId,
                richText: fusedDocument(prevPayload.richText, appending: payload.richText)
            ))
        case (.todo(let prevPayload), .code(let payload)):
            return .todo(TodoPayload(
                todoId: prevPayload.todoId,
                richText: fusedDocument(prevPayload.richText, appendingPlain: payload.text)
            ))

        case (.code(let prevPayload), .code(let payload)):
            return .code(CodePayload(
                text: prevPayload.text + payload.text,
                language: prevPayload.language
            ))
        case (.code(let prevPayload), .richText(let doc)):
            return .code(CodePayload(
                text: prevPayload.text + doc.text,
                language: prevPayload.language
            ))
        case (.code(let prevPayload), .todo(let payload)):
            return .code(CodePayload(
                text: prevPayload.text + payload.richText.text,
                language: prevPayload.language
            ))

        default:
            // fileReference/image/screenshot predecessors cannot carry text.
            return nil
        }
    }

    /// Appends a rich-text document to the previous one: runs and paragraphs
    /// shift by the previous text's scalar count (UTF-16 offsets would break
    /// on CJK/emoji); marks/link/hardBreak/style survive. Both texts are NFC
    /// at the canonical boundary, and NFC is closed under concatenation — no
    /// re-normalization needed.
    private static func fusedDocument(
        _ previous: RichTextDocument,
        appending doc: RichTextDocument
    ) -> RichTextDocument {
        let offset = previous.text.unicodeScalars.count
        let text = previous.text + doc.text
        var paragraphs = previous.paragraphs
        for paragraph in doc.paragraphs {
            let shiftedRuns = paragraph.runs.map { run in
                RichTextRun(
                    startScalar: run.startScalar + offset,
                    endScalar: run.endScalar + offset,
                    marks: run.marks,
                    link: run.link,
                    hardBreak: run.hardBreak
                )
            }
            paragraphs.append(RichTextParagraph(
                startScalar: paragraph.startScalar + offset,
                endScalar: paragraph.endScalar + offset,
                style: paragraph.style,
                runs: shiftedRuns
            ))
        }
        return RichTextDocument(text: text, paragraphs: paragraphs)
    }

    /// Appends plain text (code blocks carry no runs) as a single unstyled
    /// body paragraph.
    private static func fusedDocument(
        _ previous: RichTextDocument,
        appendingPlain text: String
    ) -> RichTextDocument {
        fusedDocument(previous, appending: RichTextDocument.plain(text))
    }
}
