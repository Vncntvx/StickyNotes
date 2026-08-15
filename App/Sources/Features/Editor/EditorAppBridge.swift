import Foundation
import AppKit
import Domain
import EditorCore

// MARK: - EditorAppBridge (T300, FR-050a/FR-054)
//
// Per tasks.md T300 and spec FR-050a/FR-054 (clarified 2026-08-07): the App
// path triggers the same operations the EditorCore tests verify.
//
// - FR-050a (empty-block removal, merge into the FOLLOWING block): the
//   editor's cursor-exit event is translated into a structural block-list
//   change via `BlockMergeOperation.decide` — the final block is never
//   removed, and removal never fires while an IME composition is active
//   (FR-063). The App groups the removal as ONE undo group.
// - FR-054 (cross-block selection): copy emits plain + rich (RTF)
//   representations containing ONLY application-supported formatting
//   (FR-053) via `CrossBlockSelectionCore`; range-delete removes only the
//   selected characters and merges emptied blocks away per FR-050a.
//
// NOTE (platform limitation, R3.9 Spike ADR 2026-08-15): SwiftUI
// `TextEditor` exposes no programmatic selection API on the macOS 26
// surface; macOS 26's `AttributedTextSelection` is a display-only binding
// for SwiftUI `Text`/`TextEditor` and cannot drive (or read) an AppKit
// `NSTextView` editor, so the canonical-model operations are wired here and
// exercised by AppTests — the same operations the EditorCore suites verify.
// See Documentation/adr/2026-08-15-macos27-ecosystem-alignment.md.

/// App-side wiring of the FR-050a/FR-054 EditorCore operations.
public enum EditorAppBridge {

    /// Applies the FR-050a empty-block removal decision when the cursor
    /// exits an emptied block. Returns the updated block list when a
    /// removal/merge was applied, or `nil` when nothing changed
    /// (noRemoval / keepFinalBlock).
    public static func applyEmptyBlockRemoval(
        blocks: [Block],
        emptiedBlockIndex: Int,
        hasIMEComposition: Bool
    ) -> [Block]? {
        let isEmpty = blocks.indices.contains(emptiedBlockIndex)
            && BlockMergeOperation.isEmpty(blocks[emptiedBlockIndex])
        let decision = BlockMergeOperation.decide(
            blocks: blocks,
            emptiedBlockIndex: emptiedBlockIndex,
            isBlockEmpty: isEmpty,
            hasIMEComposition: hasIMEComposition
        )
        switch decision {
        case .mergeWithSuccessor, .delete:
            // The emptied block's slot collapses: remove the block. The
            // caller registers ONE undo group restoring the removed block.
            var updated = blocks
            updated.remove(at: emptiedBlockIndex)
            return updated
        case .keepFinalBlock, .noRemoval:
            return nil
        }
    }

    /// FR-054 copy: writes the spanning selection to the pasteboard as
    /// plain text + RTF with only application-supported formatting (FR-053).
    /// Returns `true` when the pasteboard was written.
    @discardableResult
    public static func copySpanningSelection(
        blocks: [Block],
        selection: CrossBlockSelection,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        let plain = CrossBlockSelectionCore.selectedPlainText(blocks: blocks, selection: selection)
        guard !plain.isEmpty else { return false }
        let rtf = CrossBlockSelectionCore.richTextRepresentation(blocks: blocks, selection: selection)
        pasteboard.clearContents()
        pasteboard.setString(plain, forType: .string)
        if let data = rtf.data(using: .utf8) {
            pasteboard.setData(data, forType: .rtf)
        }
        return true
    }

    /// FR-054 range-delete: removes only the selected characters, then
    /// merges emptied blocks away per FR-050a (merge into the FOLLOWING
    /// block; remove outright when the successor is a special block). The
    /// caller groups the whole operation as ONE undo group.
    public static func deleteSpanningSelection(
        blocks: [Block],
        selection: CrossBlockSelection,
        noteId: UUID,
        deviceId: UUID
    ) -> [Block] {
        var updated = CrossBlockSelectionCore.deletingSelection(
            blocks: blocks,
            selection: selection,
            noteId: noteId,
            deviceId: deviceId
        )
        // FR-050a: any block emptied by the deletion is merged away when the
        // cursor exits it (re-evaluate from the END so index shifts do not
        // invalidate earlier decisions).
        var index = updated.count - 1
        while index >= 0 {
            if BlockMergeOperation.isEmpty(updated[index]),
               let next = applyEmptyBlockRemoval(
                   blocks: updated,
                   emptiedBlockIndex: index,
                   hasIMEComposition: false
               ) {
                updated = next
            }
            index -= 1
        }
        return updated
    }
}
