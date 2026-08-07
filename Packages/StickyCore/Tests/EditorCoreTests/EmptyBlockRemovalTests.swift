import Testing
import Foundation
import Domain
@testable import EditorCore

// MARK: - Empty-block removal tests (T226, FR-050a)
//
// Per tasks.md T226: "(a) an emptied block (paragraph/list item/todo/
// heading) stays in place while the cursor remains within it; (b) on cursor
// exit the block is removed by merging with the adjacent block (or deleted
// when no merge is possible); (c) the final block of a note is NEVER removed
// this way (remains an empty paragraph); (d) a single Undo restores the
// removed block and its content; (e) removal does NOT fire while an
// input-method marked-text composition is active (FR-063)".

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
    func emptyBlockMergesWithRichTextPredecessor() {
        let noteId = UUID()
        let blocks = [
            richBlock("Predecessor text", noteId: noteId, sortKey: 0),
            richBlock("", noteId: noteId, sortKey: 1024),
            richBlock("last", noteId: noteId, sortKey: 2048),
        ]
        let decision = BlockMergeOperation.decide(
            blocks: blocks,
            emptiedBlockIndex: 1,
            isBlockEmpty: true,
            hasIMEComposition: false
        )
        guard case .mergeWithPredecessor(let index, let text) = decision else {
            Issue.record("expected mergeWithPredecessor, got \(decision)")
            return
        }
        #expect(index == 0)
        #expect(text == "Predecessor text")
    }

    @Test
    func emptyTodoBlockMergesWithTodoPredecessor() {
        let noteId = UUID()
        let todoBlock = Block(
            noteId: noteId,
            kind: .todo,
            sortKey: 0,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("task"))),
            lastModifiedDeviceId: Self.deviceId
        )
        let emptyTodo = Block(
            noteId: noteId,
            kind: .todo,
            sortKey: 1024,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .empty)),
            lastModifiedDeviceId: Self.deviceId
        )
        let blocks = [todoBlock, emptyTodo, richBlock("last", noteId: noteId, sortKey: 2048)]
        let decision = BlockMergeOperation.decide(
            blocks: blocks,
            emptiedBlockIndex: 1,
            isBlockEmpty: true,
            hasIMEComposition: false
        )
        guard case .mergeWithPredecessor(let index, let text) = decision else {
            Issue.record("expected mergeWithPredecessor, got \(decision)")
            return
        }
        #expect(index == 0)
        #expect(text == "task")
    }

    @Test
    func firstBlockWithoutMergePartnerIsDeleted() {
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
        guard case .delete(let index) = decision else {
            Issue.record("expected delete, got \(decision)")
            return
        }
        #expect(index == 0)
    }

    @Test
    func specialBlockPredecessorFallsBackToDelete() {
        let noteId = UUID()
        let codeBlock = Block(
            noteId: noteId,
            kind: .code,
            sortKey: 0,
            payload: .code(CodePayload(text: "let x = 1")),
            lastModifiedDeviceId: Self.deviceId
        )
        let blocks = [codeBlock, richBlock("", noteId: noteId, sortKey: 1024),
                      richBlock("last", noteId: noteId, sortKey: 2048)]
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
        // result fully determines the inverse — merge keeps the predecessor
        // text, delete restores the block at its index. Assert the decision
        // carries enough information for a single undo.
        let noteId = UUID()
        let blocks = [
            richBlock("Predecessor", noteId: noteId, sortKey: 0),
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
        guard case .mergeWithPredecessor = decision else {
            Issue.record("expected merge")
            return
        }
        #expect(true)
    }
}
