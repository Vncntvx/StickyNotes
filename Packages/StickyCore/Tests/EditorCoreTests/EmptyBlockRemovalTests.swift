import Testing
import Foundation
import Domain
@testable import EditorCore

// MARK: - Empty-block removal tests (T226/T300, FR-050a)
//
// Per tasks.md T226: "(a) an emptied block (paragraph/list item/todo/
// heading) stays in place while the cursor remains within it; (b) on cursor
// exit the block is removed by merging with the adjacent block (or deleted
// when no merge is possible); (c) the final block of a note is NEVER removed
// this way (remains an empty paragraph); (d) a single Undo restores the
// removed block and its content; (e) removal does NOT fire while an
// input-method marked-text composition is active (FR-063)".
//
// Merge direction (clarified 2026-08-07): the emptied block merges into the
// FOLLOWING block; when the following block cannot accept the merge (a
// special block — code/file-reference/image/screenshot), the emptied block
// is removed outright with no content merge.

@Suite struct EmptyBlockRemovalTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    private func richBlock(_ text: String, noteId: UUID, sortKey: Int) -> Block {
        Block(noteId: noteId, kind: .richText, sortKey: sortKey,
              payload: .richText(.plain(text)), lastModifiedDeviceId: Self.deviceId)
    }

    @Test
    func emptiedBlockStaysWhileCursorWithinIt() {
        // The decision fires only on cursor EXIT; while inside, nothing
        // happens — the App layer simply does not invoke the operation.
        // Assert the core treats a non-empty (or not-yet-exited) block as
        // no-removal.
        let noteId = UUID()
        let blocks = [
            richBlock("first", noteId: noteId, sortKey: 0),
            richBlock("", noteId: noteId, sortKey: 1024),
            richBlock("last", noteId: noteId, sortKey: 2048),
        ]
        let decision = BlockMergeOperation.decide(
            blocks: blocks,
            emptiedBlockIndex: 1,
            isBlockEmpty: false,   // cursor still inside → not emptied yet
            hasIMEComposition: false
        )
        #expect(decision == .noRemoval)
    }

    @Test
    func emptyBlockMergesIntoFollowingRichTextBlock() {
        let noteId = UUID()
        let blocks = [
            richBlock("first", noteId: noteId, sortKey: 0),
            richBlock("", noteId: noteId, sortKey: 1024),      // emptied
            richBlock("Successor text", noteId: noteId, sortKey: 2048),
        ]
        let decision = BlockMergeOperation.decide(
            blocks: blocks,
            emptiedBlockIndex: 1,
            isBlockEmpty: true,
            hasIMEComposition: false
        )
        // Clarified direction: merge into the FOLLOWING block, never the
        // predecessor.
        guard case .mergeWithSuccessor(let index) = decision else {
            Issue.record("expected mergeWithSuccessor, got \(decision)")
            return
        }
        #expect(index == 2)
    }

    @Test
    func emptyTodoBlockMergesIntoFollowingTodoBlock() {
        let noteId = UUID()
        let emptyTodo = Block(
            noteId: noteId,
            kind: .todo,
            sortKey: 1024,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .empty)),
            lastModifiedDeviceId: Self.deviceId
        )
        let todoBlock = Block(
            noteId: noteId,
            kind: .todo,
            sortKey: 2048,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("task"))),
            lastModifiedDeviceId: Self.deviceId
        )
        let blocks = [richBlock("first", noteId: noteId, sortKey: 0), emptyTodo, todoBlock]
        let decision = BlockMergeOperation.decide(
            blocks: blocks,
            emptiedBlockIndex: 1,
            isBlockEmpty: true,
            hasIMEComposition: false
        )
        guard case .mergeWithSuccessor(let index) = decision else {
            Issue.record("expected mergeWithSuccessor, got \(decision)")
            return
        }
        #expect(index == 2)
    }

    @Test
    func firstEmptyBlockMergesIntoFollowingBlock() {
        // The first block has no predecessor — under the clarified rule it
        // merges into its FOLLOWING block when that block is text-bearing.
        let noteId = UUID()
        let blocks = [
            richBlock("", noteId: noteId, sortKey: 0),   // first block, empty
            richBlock("second", noteId: noteId, sortKey: 1024),
        ]
        let decision = BlockMergeOperation.decide(
            blocks: blocks,
            emptiedBlockIndex: 0,
            isBlockEmpty: true,
            hasIMEComposition: false
        )
        guard case .mergeWithSuccessor(let index) = decision else {
            Issue.record("expected mergeWithSuccessor, got \(decision)")
            return
        }
        #expect(index == 1)
    }

    @Test
    func specialBlockSuccessorFallsBackToDelete() {
        let noteId = UUID()
        let codeBlock = Block(
            noteId: noteId,
            kind: .code,
            sortKey: 2048,
            payload: .code(CodePayload(text: "let x = 1")),
            lastModifiedDeviceId: Self.deviceId
        )
        // The emptied block's FOLLOWING block is a code block — a special
        // block that cannot accept a text merge: remove outright.
        let blocks = [richBlock("first", noteId: noteId, sortKey: 0),
                      richBlock("", noteId: noteId, sortKey: 1024), codeBlock]
        let decision = BlockMergeOperation.decide(
            blocks: blocks,
            emptiedBlockIndex: 1,
            isBlockEmpty: true,
            hasIMEComposition: false
        )
        guard case .delete(let index) = decision else {
            Issue.record("expected delete, got \(decision)")
            return
        }
        #expect(index == 1)
    }

    @Test
    func firstEmptyBlockWithSpecialSuccessorIsDeleted() {
        let noteId = UUID()
        let screenshotBlock = Block(
            noteId: noteId,
            kind: .screenshot,
            sortKey: 1024,
            payload: .screenshot(ScreenshotPayload(
                originalAssetId: UUID(),
                thumbnailAssetId: UUID(),
                applicationName: nil,
                windowTitle: nil,
                caption: nil,
                capturedAt: Date(),
                isCover: false
            )),
            lastModifiedDeviceId: Self.deviceId
        )
        let blocks = [richBlock("", noteId: noteId, sortKey: 0), screenshotBlock]
        let decision = BlockMergeOperation.decide(
            blocks: blocks,
            emptiedBlockIndex: 0,
            isBlockEmpty: true,
            hasIMEComposition: false
        )
        guard case .delete(let index) = decision else {
            Issue.record("expected delete, got \(decision)")
            return
        }
        #expect(index == 0)
    }

    @Test
    func finalBlockIsNeverRemoved() {
        let noteId = UUID()
        let blocks = [
            richBlock("only", noteId: noteId, sortKey: 0),
            richBlock("", noteId: noteId, sortKey: 1024),  // final block
        ]
        let decision = BlockMergeOperation.decide(
            blocks: blocks,
            emptiedBlockIndex: 1,
            isBlockEmpty: true,
            hasIMEComposition: false
        )
        #expect(decision == .keepFinalBlock, "the final block remains an empty paragraph (FR-050a)")

        // Even a single empty block on its own is kept.
        let single = [richBlock("", noteId: noteId, sortKey: 0)]
        #expect(BlockMergeOperation.decide(
            blocks: single,
            emptiedBlockIndex: 0,
            isBlockEmpty: true,
            hasIMEComposition: false
        ) == .keepFinalBlock)
    }

    @Test
    func removalSuppressedDuringIMEComposition() {
        let noteId = UUID()
        let blocks = [
            richBlock("first", noteId: noteId, sortKey: 0),
            richBlock("", noteId: noteId, sortKey: 1024),
            richBlock("last", noteId: noteId, sortKey: 2048),
        ]
        let decision = BlockMergeOperation.decide(
            blocks: blocks,
            emptiedBlockIndex: 1,
            isBlockEmpty: true,
            hasIMEComposition: true   // FR-063
        )
        #expect(decision == .noRemoval)
    }

    @Test
    func singleUndoRestoresRemovedBlock() {
        // The App layer registers the inverse (block restored with its
        // content) as ONE undo operation. The core's contract: the decision
        // result fully determines the inverse — merge keeps the successor
        // slot, delete restores the block at its index. Assert the decision
        // carries enough information for a single undo.
        let noteId = UUID()
        let blocks = [
            richBlock("first", noteId: noteId, sortKey: 0),
            richBlock("", noteId: noteId, sortKey: 1024),
            richBlock("last", noteId: noteId, sortKey: 2048),
        ]
        let decision = BlockMergeOperation.decide(
            blocks: blocks,
            emptiedBlockIndex: 1,
            isBlockEmpty: true,
            hasIMEComposition: false
        )
        // One decision = one undo group.
        guard case .mergeWithSuccessor(let successorIndex) = decision else {
            Issue.record("expected merge")
            return
        }
        #expect(successorIndex == 2)

        // Delete-outright decision also carries the undo info (block index).
        let special = Block(
            noteId: noteId,
            kind: .image,
            sortKey: 2048,
            payload: .image(EmbeddedImagePayload(
                originalAssetId: UUID(),
                thumbnailAssetId: UUID(),
                caption: nil
            )),
            lastModifiedDeviceId: Self.deviceId
        )
        let specialBlocks = [richBlock("first", noteId: noteId, sortKey: 0),
                             richBlock("", noteId: noteId, sortKey: 1024), special]
        let deleteDecision = BlockMergeOperation.decide(
            blocks: specialBlocks,
            emptiedBlockIndex: 1,
            isBlockEmpty: true,
            hasIMEComposition: false
        )
        guard case .delete(let index) = deleteDecision else {
            Issue.record("expected delete")
            return
        }
        #expect(index == 1)
    }
}
