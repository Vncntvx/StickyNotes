import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

// MARK: - TodoRepository tests (T056)
//
// Per tasks.md T056: "Domain test: TodoItem stable UUID across identical
// text/text-change/reorder (FR-071) + hierarchy validation (no cycles,
// depth bound, no orphaned children)."
//
// Verifies:
// - Inserting a todo returns the same UUID across text edits and reorders
//   (identity is separate from text — FR-071).
// - Hierarchy validation: parent must be in the same note; cycles rejected;
//   depth ≤ maxDepth enforced.
// - Deleting a parent reparents children to grandparent (no orphaned
//   children — data-model.md §TodoItem validation).
// - Reorder updates sortKey; reparent updates parentTodoId + depth.

@Suite struct TodoRepositoryTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    private func freshRepo() async throws -> (SQLiteNoteRepository, SQLiteTodoRepository, DatabaseStore) {
        let store = try DatabaseStore.inMemory()
        let migrator = InitialSchema.migrator()
        try migrator.migrate(store.dbPool)
        let fts = FullTextSearch(dbPool: store.dbPool)
        let noteRepo = SQLiteNoteRepository(store: store, fullTextSearch: fts)
        let todoRepo = SQLiteTodoRepository(store: store)
        return (noteRepo, todoRepo, store)
    }

    // MARK: - Identity stability (FR-071)

    @Test
    func todoIdStableAcrossTextAndReorder() async throws {
        let (noteRepo, todoRepo, _) = try await freshRepo()
        let noteId = UUID()
        try await noteRepo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))

        // Create a todo block + its TodoItem.
        let blockId = UUID()
        let todoId = UUID()
        let block = Block(id: blockId, noteId: noteId, kind: .todo, sortKey: 0,
                          payload: .todo(TodoPayload(todoId: todoId, richText: .plain("buy milk"))),
                          lastModifiedDeviceId: Self.deviceId)
        try await noteRepo.insertBlock(block)
        try await todoRepo.insert(TodoItem(id: todoId, noteId: noteId, blockId: blockId, sortKey: 0, lastModifiedDeviceId: Self.deviceId))

        // Edit the text (block payload) — the todoId must stay the same.
        var editedBlock = block
        editedBlock.payload = .todo(TodoPayload(todoId: todoId, richText: .plain("buy oat milk")))
        try await noteRepo.updateBlock(editedBlock, modifyingDeviceId: Self.deviceId)
        let todoAfterText = try await todoRepo.fetchTodo(blockId: blockId)!
        #expect(todoAfterText.id == todoId, "todo id stable across text edit (FR-071)")

        // Reorder — the todoId must stay the same.
        try await todoRepo.reorder(todoId: todoId, newSortKey: 5000, deviceId: Self.deviceId)
        let todoAfterReorder = try await todoRepo.fetchTodo(blockId: blockId)!
        #expect(todoAfterReorder.id == todoId, "todo id stable across reorder (FR-071)")
        #expect(todoAfterReorder.sortKey == 5000)
    }

    // MARK: - Hierarchy validation

    @Test
    func parentMustBeInSameNote() async throws {
        let (noteRepo, todoRepo, _) = try await freshRepo()
        let noteA = UUID()
        let noteB = UUID()
        try await noteRepo.create(Note(id: noteA, lastModifiedDeviceId: Self.deviceId))
        try await noteRepo.create(Note(id: noteB, lastModifiedDeviceId: Self.deviceId))

        // A parent todo in note A.
        let parentBlockId = UUID()
        let parentId = UUID()
        try await noteRepo.insertBlock(Block(id: parentBlockId, noteId: noteA, kind: .todo, sortKey: 0, payload: .todo(TodoPayload(todoId: parentId, richText: .plain("parent"))), lastModifiedDeviceId: Self.deviceId))
        try await todoRepo.insert(TodoItem(id: parentId, noteId: noteA, blockId: parentBlockId, sortKey: 0, lastModifiedDeviceId: Self.deviceId))

        // A child block in note B trying to reparent to the note-A parent.
        let childBlockId = UUID()
        let childId = UUID()
        try await noteRepo.insertBlock(Block(id: childBlockId, noteId: noteB, kind: .todo, sortKey: 0, payload: .todo(TodoPayload(todoId: childId, richText: .plain("child"))), lastModifiedDeviceId: Self.deviceId))
        try await todoRepo.insert(TodoItem(id: childId, noteId: noteB, blockId: childBlockId, sortKey: 0, lastModifiedDeviceId: Self.deviceId))

        do {
            try await todoRepo.reparent(todoId: childId, newParentId: parentId, deviceId: Self.deviceId)
            Issue.record("Reparent across notes should be rejected")
        } catch {
            // Expected.
            #expect(true)
        }
    }

    @Test
    func cyclesRejected() async throws {
        let (noteRepo, todoRepo, _) = try await freshRepo()
        let noteId = UUID()
        try await noteRepo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))

        // Two todos that try to be each other's parents.
        let b1 = UUID(); let b2 = UUID()
        let t1 = UUID(); let t2 = UUID()
        try await noteRepo.insertBlock(Block(id: b1, noteId: noteId, kind: .todo, sortKey: 0, payload: .todo(TodoPayload(todoId: t1, richText: .plain("1"))), lastModifiedDeviceId: Self.deviceId))
        try await noteRepo.insertBlock(Block(id: b2, noteId: noteId, kind: .todo, sortKey: 1024, payload: .todo(TodoPayload(todoId: t2, richText: .plain("2"))), lastModifiedDeviceId: Self.deviceId))
        try await todoRepo.insert(TodoItem(id: t1, noteId: noteId, blockId: b1, sortKey: 0, lastModifiedDeviceId: Self.deviceId))
        try await todoRepo.insert(TodoItem(id: t2, noteId: noteId, blockId: b2, sortKey: 1024, lastModifiedDeviceId: Self.deviceId))

        // t1 → parent t2
        try await todoRepo.reparent(todoId: t1, newParentId: t2, deviceId: Self.deviceId)
        // Now try t2 → parent t1 (cycle).
        do {
            try await todoRepo.reparent(todoId: t2, newParentId: t1, deviceId: Self.deviceId)
            Issue.record("Cycle should be rejected")
        } catch {
            #expect(true)
        }
    }

    @Test
    func depthBoundEnforced() async throws {
        let (noteRepo, todoRepo, _) = try await freshRepo()
        let noteId = UUID()
        try await noteRepo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))

        // Build a chain at exactly maxDepth (depths 0..maxDepth-1).
        // Then trying to reparent a new todo to the deepest one would give
        // depth = maxDepth, which is ALLOWED (depth ≤ maxDepth). So we build
        // one more level (depth = maxDepth) and then try to add depth+1,
        // which MUST be rejected.
        var prevId: UUID? = nil
        for i in 0...TodoHierarchy.maxDepth {
            let bId = UUID(); let tId = UUID()
            try await noteRepo.insertBlock(Block(id: bId, noteId: noteId, kind: .todo, sortKey: i * 100, payload: .todo(TodoPayload(todoId: tId, richText: .plain("lvl \(i)"))), lastModifiedDeviceId: Self.deviceId))
            try await todoRepo.insert(TodoItem(id: tId, noteId: noteId, blockId: bId, parentTodoId: prevId, sortKey: i * 100, depth: i, lastModifiedDeviceId: Self.deviceId))
            prevId = tId
        }

        // `prevId` is now the todo at depth maxDepth. Trying to reparent a
        // new todo to it would give depth = maxDepth + 1, which MUST be rejected.
        let bOver = UUID(); let tOver = UUID()
        try await noteRepo.insertBlock(Block(id: bOver, noteId: noteId, kind: .todo, sortKey: 999_999, payload: .todo(TodoPayload(todoId: tOver, richText: .plain("over"))), lastModifiedDeviceId: Self.deviceId))
        try await todoRepo.insert(TodoItem(id: tOver, noteId: noteId, blockId: bOver, sortKey: 999_999, lastModifiedDeviceId: Self.deviceId))
        do {
            try await todoRepo.reparent(todoId: tOver, newParentId: prevId, deviceId: Self.deviceId)
            Issue.record("Depth beyond maxDepth should be rejected")
        } catch {
            #expect(true)
        }
    }

    @Test
    func deletingParentReparentsChildrenToGrandparent() async throws {
        let (noteRepo, todoRepo, _) = try await freshRepo()
        let noteId = UUID()
        try await noteRepo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))

        // grandparent → parent → child
        let gBlock = UUID(); let gId = UUID()
        let pBlock = UUID(); let pId = UUID()
        let cBlock = UUID(); let cId = UUID()
        try await noteRepo.insertBlock(Block(id: gBlock, noteId: noteId, kind: .todo, sortKey: 0,    payload: .todo(TodoPayload(todoId: gId, richText: .plain("g"))), lastModifiedDeviceId: Self.deviceId))
        try await noteRepo.insertBlock(Block(id: pBlock, noteId: noteId, kind: .todo, sortKey: 1024, payload: .todo(TodoPayload(todoId: pId, richText: .plain("p"))), lastModifiedDeviceId: Self.deviceId))
        try await noteRepo.insertBlock(Block(id: cBlock, noteId: noteId, kind: .todo, sortKey: 2048, payload: .todo(TodoPayload(todoId: cId, richText: .plain("c"))), lastModifiedDeviceId: Self.deviceId))
        try await todoRepo.insert(TodoItem(id: gId, noteId: noteId, blockId: gBlock, sortKey: 0,    depth: 0, lastModifiedDeviceId: Self.deviceId))
        try await todoRepo.insert(TodoItem(id: pId, noteId: noteId, blockId: pBlock, parentTodoId: gId, sortKey: 1024, depth: 1, lastModifiedDeviceId: Self.deviceId))
        try await todoRepo.insert(TodoItem(id: cId, noteId: noteId, blockId: cBlock, parentTodoId: pId, sortKey: 2048, depth: 2, lastModifiedDeviceId: Self.deviceId))

        // Delete the parent. The child should reparent to the grandparent.
        try await todoRepo.delete(id: pId)

        let child = try await todoRepo.fetchTodo(blockId: cBlock)!
        #expect(child.parentTodoId == gId, "child reparented to grandparent (no orphaned children)")
        #expect(child.depth == 1)
    }

    @Test
    func setCompleteUpdatesCompletionState() async throws {
        let (noteRepo, todoRepo, _) = try await freshRepo()
        let noteId = UUID()
        try await noteRepo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))
        let bId = UUID(); let tId = UUID()
        try await noteRepo.insertBlock(Block(id: bId, noteId: noteId, kind: .todo, sortKey: 0, payload: .todo(TodoPayload(todoId: tId, richText: .plain("task"))), lastModifiedDeviceId: Self.deviceId))
        try await todoRepo.insert(TodoItem(id: tId, noteId: noteId, blockId: bId, sortKey: 0, lastModifiedDeviceId: Self.deviceId))

        try await todoRepo.setComplete(todoId: tId, isComplete: true, deviceId: Self.deviceId)
        let after = try await todoRepo.fetchTodo(blockId: bId)!
        #expect(after.isComplete == true)
        #expect(after.id == tId, "id stable across completion toggle (FR-071)")
    }
}
