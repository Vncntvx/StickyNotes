import Foundation
import Domain

// MARK: - CrossBlockSelection (T259)
//
// Per tasks.md T259 and spec FR-054 (clarified 2026-08-07): text selection
// MAY span block boundaries (paragraphs, list items, todo items, headings).
// Copying a spanning selection places both plain-text and rich-text (RTF/
// HTML) representations on the clipboard, where the rich representation
// contains only application-supported formatting (FR-053). Deleting a
// spanning selection removes only the selected characters; an emptied block
// is merged away per the FR-050a rules (single Undo restores). The trailing
// empty padding paragraph is never selectable.
//
// This is the pure selection model: per-block character offsets computed
// over the canonical block list. The App layer wires it into the SwiftUI
// TextEditor's selection (RichTextBlockView) and clipboard.

/// A selection spanning one or more blocks. Per-block scalar ranges.
public struct CrossBlockSelection: Sendable, Equatable {
    /// The blocks in selection order (by sortKey), each with its selected
    /// scalar range within that block's text.
    public let selections: [(blockId: UUID, range: Range<Int>)]

    public init(selections: [(blockId: UUID, range: Range<Int>)]) {
        self.selections = selections
    }

    public static func == (lhs: CrossBlockSelection, rhs: CrossBlockSelection) -> Bool {
        guard lhs.selections.count == rhs.selections.count else { return false }
        for (l, r) in zip(lhs.selections, rhs.selections) {
            guard l.blockId == r.blockId, l.range == r.range else { return false }
        }
        return true
    }
}

/// The selection core for FR-054.
public enum CrossBlockSelectionCore {

    /// The trailing empty padding paragraph is NEVER selectable (FR-054).
    /// Returns `true` when the given block index is the last block AND it
    /// is empty.
    public static func isTrailingPaddingParagraph(blocks: [Block], index: Int) -> Bool {
        guard index == blocks.count - 1 else { return false }
        guard index >= 0 else { return false }
        return BlockMergeOperation.isEmpty(blocks[index])
    }

    /// Builds the selectable plain text for a spanning selection.
    /// Block texts are joined with newlines; the trailing padding paragraph
    /// is excluded from the selectable range.
    public static func selectedPlainText(
        blocks: [Block],
        selection: CrossBlockSelection
    ) -> String {
        var parts: [String] = []
        for (index, block) in blocks.enumerated() {
            if isTrailingPaddingParagraph(blocks: blocks, index: index) { continue }
            guard let picked = selection.selections.first(where: { $0.blockId == block.id }) else { continue }
            let text = blockText(block)
            let scalars = Array(text.unicodeScalars)
            let clamped = Range(
                uncheckedBounds: (
                    min(max(picked.range.lowerBound, 0), scalars.count),
                    min(max(picked.range.upperBound, 0), scalars.count)
                )
            )
            guard clamped.lowerBound < clamped.upperBound else { continue }
            let sub = scalars[clamped.lowerBound..<clamped.upperBound]
            var s = ""
            s.unicodeScalars.append(contentsOf: sub)
            parts.append(s)
        }
        return parts.joined(separator: "\n")
    }

    /// Deletes a spanning selection: removes only the selected characters
    /// from the block texts, returning the updated blocks. An emptied block
    /// is merged away per the FR-050a rules (the caller groups the whole
    /// operation as ONE undo).
    public static func deletingSelection(
        blocks: [Block],
        selection: CrossBlockSelection,
        noteId: UUID,
        deviceId: UUID
    ) -> [Block] {
        var updated = blocks
        for (index, block) in blocks.enumerated() {
            guard let picked = selection.selections.first(where: { $0.blockId == block.id }) else { continue }
            let text = blockText(block)
            let scalars = Array(text.unicodeScalars)
            let clamped = Range(
                uncheckedBounds: (
                    min(max(picked.range.lowerBound, 0), scalars.count),
                    min(max(picked.range.upperBound, 0), scalars.count)
                )
            )
            guard clamped.lowerBound < clamped.upperBound else { continue }
            var remaining = scalars
            remaining.removeSubrange(clamped.lowerBound..<clamped.upperBound)
            var newText = ""
            newText.unicodeScalars.append(contentsOf: remaining)
            updated[index] = withText(newText, block: block, deviceId: deviceId)
        }
        return updated
    }

    /// The rich-text (RTF/HTML) clipboard representation with ONLY
    /// application-supported formatting (FR-053). The App layer hands this
    /// to NSPasteboard as `public.rtf`. The canonical plain-text
    /// representation is `selectedPlainText`.
    ///
    /// The RTF markup uses only the supported marks (bold/italic/underline/
    /// strikethrough/inline code as Courier New).
    public static func richTextRepresentation(
        blocks: [Block],
        selection: CrossBlockSelection
    ) -> String {
        let plain = selectedPlainText(blocks: blocks, selection: selection)
        var rtf = "{\\rtf1\\ansi\\ansicpg1252\\cocoartf2700\\cocoasubrtf830"
        rtf += "\\{\\fonttbl\\f0\\fnil\\fcharset0 Helvetica;\\f1\\fmodern Courier New;}"
        rtf += "\\{\\colortbl;\\red0\\green0\\blue0;}"
        // Bold/italic/underline/strikethrough commands per selected marks.
        var segments: [String] = []
        // Build per-block segments with marks from the canonical runs.
        for (index, block) in blocks.enumerated() {
            if isTrailingPaddingParagraph(blocks: blocks, index: index) { continue }
            guard let picked = selection.selections.first(where: { $0.blockId == block.id }) else { continue }
            guard case .richText(let doc) = block.payload else { continue }
            let scalars = Array(doc.text.unicodeScalars)
            let clamped = Range(
                uncheckedBounds: (
                    min(max(picked.range.lowerBound, 0), scalars.count),
                    min(max(picked.range.upperBound, 0), scalars.count)
                )
            )
            guard clamped.lowerBound < clamped.upperBound else { continue }
            // Emit runs that intersect the selection, wrapped in RTF
            // commands per mark.
            var blockRTF = ""
            var cursor = clamped.lowerBound
            let intersectingRuns = doc.paragraphs
                .flatMap(\.runs)
                .filter { $0.endScalar > clamped.lowerBound && $0.startScalar < clamped.upperBound }
                .sorted { $0.startScalar < $1.startScalar }
            for run in intersectingRuns {
                let start = max(run.startScalar, clamped.lowerBound)
                let end = min(run.endScalar, clamped.upperBound)
                if start > cursor {
                    // unstyled gap
                    let gap = String(String.UnicodeScalarView(scalars[cursor..<start]))
                    blockRTF += escapeRTF(gap)
                    cursor = start
                }
                let segment = String(String.UnicodeScalarView(scalars[start..<end]))
                cursor = end
                var prefix = ""
                var suffix = ""
                if run.marks.contains(.bold) { prefix += "\\b "; suffix = "\\b0 " + suffix }
                if run.marks.contains(.italic) { prefix += "\\i "; suffix = "\\i0 " + suffix }
                if run.marks.contains(.underline) { prefix += "\\ul "; suffix = "\\ulnone " + suffix }
                if run.marks.contains(.strikethrough) { prefix += "\\strike "; suffix = "\\strike0 " + suffix }
                if run.marks.contains(.inlineCode) { prefix += "\\f1 "; suffix = "\\f0 " + suffix }
                blockRTF += prefix + escapeRTF(segment) + suffix
            }
            if cursor < clamped.upperBound {
                let rest = String(String.UnicodeScalarView(scalars[cursor..<clamped.upperBound]))
                blockRTF += escapeRTF(rest)
            }
            if blockRTF.isEmpty {
                blockRTF = escapeRTF(String(String.UnicodeScalarView(scalars[clamped])))
            }
            segments.append(blockRTF)
        }
        if segments.isEmpty {
            rtf += escapeRTF(plain)
        } else {
            rtf += segments.joined(separator: "\\line ")
        }
        rtf += "}"
        return rtf
    }

    // MARK: - Block text helpers

    /// The selectable plain text of a block (per canonical payload).
    public static func blockText(_ block: Block) -> String {
        switch block.payload {
        case .richText(let doc): return doc.text
        case .todo(let payload): return payload.richText.text
        case .code(let payload): return payload.text
        case .fileReference(let ref): return ref.displayName
        case .image(let image): return image.caption ?? ""
        case .screenshot(let shot): return shot.caption ?? ""
        }
    }

    private static func withText(_ text: String, block: Block, deviceId: UUID) -> Block {
        let newPayload: CanonicalBlockPayload
        switch block.payload {
        case .richText:
            newPayload = .richText(RichTextDocument.plain(text))
        case .todo(let payload):
            newPayload = .todo(TodoPayload(todoId: payload.todoId, richText: RichTextDocument.plain(text)))
        case .code(let payload):
            newPayload = .code(CodePayload(text: text, language: payload.language))
        case .fileReference, .image, .screenshot:
            return block
        }
        return Block(
            id: block.id,
            noteId: block.noteId,
            kind: block.kind,
            sortKey: block.sortKey,
            payload: newPayload,
            versionId: block.versionId,
            parentVersionId: block.parentVersionId,
            lastModifiedDeviceId: deviceId,
            createdAt: block.createdAt,
            modifiedAt: Date()
        )
    }

    /// Escapes RTF-special characters.
    static func escapeRTF(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "{":  out += "\\{"
            case "}":  out += "\\}"
            case "\n": out += "\\line "
            default:
                if scalar.value < 128 {
                    out.unicodeScalars.append(scalar)
                } else {
                    out += String(format: "\\u%ld?", Int32(scalar.value))
                }
            }
        }
        return out
    }
}
