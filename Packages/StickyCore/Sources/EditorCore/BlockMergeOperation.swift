import Foundation
import Domain

// MARK: - BlockMergeOperation (T235)
//
// Per tasks.md T235 and spec FR-050a (clarified 2026-08-07): when the cursor
// leaves an emptied block (paragraph/list item/todo/heading), the block is
// removed by merging with the adjacent block (or deleted when no merge is
// possible). The FINAL block of a note is never removed this way — it
// remains an empty paragraph. Every automatic removal is reversible with a
// single Undo, and removal never fires while an input-method composition is
// active (FR-063).
//
// This is the pure decision core: it computes the merge result from the
// ordered blocks + the emptied block index. The App layer (RichTextBlockView)
// supplies the cursor-exit event and the IME marked-range state, then
// applies the computed result as ONE undo group.

/// The computed result of an empty-block removal.
public enum BlockMergeResult: Sendable, Equatable {
    /// The block was removed by merging with its predecessor: the merged
    /// content is `mergedText` (the predecessor's text + the emptied
    /// block's residual text), and the merge happens at the predecessor
    /// block index `predecessorIndex`. Both blocks collapse into one.
    case mergeWithPredecessor(predecessorIndex: Int, mergedText: String)

    /// No merge was possible (e.g. the block is the first and has no
    /// predecessor, or the predecessor is a special block): the emptied
    /// block is deleted outright.
    case delete(blockIndex: Int)

    /// The block must NOT be removed: it is the final block of the note
    /// (FR-050a: the final block remains an empty paragraph).
    case keepFinalBlock

    /// The removal is suppressed because an input-method composition is
    /// active (FR-063) or the block is not empty.
    case noRemoval
}

/// The empty-block removal decision core (FR-050a).
public enum BlockMergeOperation {

    /// Decides what happens when the cursor exits an emptied block.
    ///
    /// - Parameters:
    ///   - blocks: the note's ordered blocks (by sortKey).
    ///   - emptiedBlockIndex: the index of the block the cursor left.
    ///   - isBlockEmpty: whether the block is truly empty (no meaningful
    ///     content per FR-012a semantics).
    ///   - hasIMEComposition: whether an input-method marked text is active
    ///     (FR-063 — removal is suppressed while composing).
    /// - Returns: the merge/delete/keep decision.
    public static func decide(
        blocks: [Block],
        emptiedBlockIndex: Int,
        isBlockEmpty: Bool,
        hasIMEComposition: Bool
    ) -> BlockMergeResult {
        guard blocks.indices.contains(emptiedBlockIndex) else { return .noRemoval }
        guard !hasIMEComposition else { return .noRemoval }  // FR-063
        guard isBlockEmpty else { return .noRemoval }

        // FR-050a: the final block is never removed.
        guard emptiedBlockIndex < blocks.count - 1 else { return .keepFinalBlock }

        // First block with no predecessor: no merge partner — delete.
        guard emptiedBlockIndex > 0 else { return .delete(blockIndex: 0) }

        // Merge with the predecessor when it is a text-bearing block
        // (rich text / todo / heading). The emptied block's residual text
        // (none, it's empty) merges into the predecessor.
        let predecessor = blocks[emptiedBlockIndex - 1]
        switch predecessor.payload {
        case .richText(let doc):
            return .mergeWithPredecessor(predecessorIndex: emptiedBlockIndex - 1, mergedText: doc.text)
        case .todo(let payload):
            return .mergeWithPredecessor(predecessorIndex: emptiedBlockIndex - 1, mergedText: payload.richText.text)
        default:
            // Special block predecessor (code/file/image/screenshot): no
            // text merge possible — delete the emptied block.
            return .delete(blockIndex: emptiedBlockIndex)
        }
    }

    /// Whether a block is empty per FR-012a semantics: no non-whitespace
    /// characters in its text payload. (Todo/code/file/image/screenshot
    /// blocks count as meaningful by presence — they are never "empty".)
    public static func isEmpty(_ block: Block) -> Bool {
        switch block.payload {
        case .richText(let doc):
            return doc.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .todo(let payload):
            return payload.richText.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .code(let payload):
            return payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .fileReference, .image, .screenshot:
            return false
        }
    }
}
