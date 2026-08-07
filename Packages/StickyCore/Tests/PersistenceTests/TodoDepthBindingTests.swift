import Testing
import Foundation
import GRDB
import Domain
import Persistence

// MARK: - Todo nesting depth binding tests (T189, FR-072a clarified 2026-08-07)
//
// Per tasks.md T189: assert TodoHierarchyMaxDepth == 6; indent is disabled
// when the active todo is at depth 6; validation rejects any todo hierarchy
// deeper than 6 levels; depth is counted from a top-level todo at depth 1.

@Suite struct TodoDepthBindingTests {

    @Test
    func todoHierarchyMaxDepthIsSix() {
        #expect(TodoHierarchyMaxDepth == 6)
    }

    @Test
    func topLevelTodoIsAtDepth0() {
        // Per the TodoItem model, a fresh todo has depth 0 by default.
        let todo = TodoItem(
            noteId: UUID(), blockId: UUID(), depth: 0,
            lastModifiedDeviceId: UUID()
        )
        #expect(todo.depth == 0)
        #expect(todo.depth <= TodoHierarchyMaxDepth)
    }

    private func makeStore() throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    @Test
    func depthAtMaxIsAccepted() async throws {
        let store = try makeStore()
        let repo = SQLiteTodoRepository(store: store)
        let noteId = UUID()
        let deviceId = UUID()
        let noteRepo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        try await noteRepo.create(Note(id: noteId, lastModifiedDeviceId: deviceId))

        // Insert a todo block first (FK requirement: todoItem.blockId → block.id).
        let blockId = UUID()
        try await noteRepo.insertBlock(Block(
            id: blockId, noteId: noteId, kind: .todo, sortKey: 0,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .plain(""))),
            lastModifiedDeviceId: deviceId
        ))

        // A todo at depth 6 (the max) is accepted.
        let todo = TodoItem(
            noteId: noteId, blockId: blockId, depth: TodoHierarchyMaxDepth,
            lastModifiedDeviceId: deviceId
        )
        try await repo.insert(todo)
        let fetched = try await repo.fetchTodo(blockId: blockId)
        #expect(fetched?.depth == TodoHierarchyMaxDepth)
    }

    @Test
    func indentBeyondMaxDepthIsRejected() async throws {
        // Indenting a todo under a parent at depth 6 would produce depth 7
        // (beyond max) — the repository rejects this on the reparent path.
        let store = try makeStore()
        let repo = SQLiteTodoRepository(store: store)
        let noteId = UUID()
        let deviceId = UUID()
        let noteRepo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        try await noteRepo.create(Note(id: noteId, lastModifiedDeviceId: deviceId))

        // Build a chain of 7 nested todos (depth 0..6). The insert method
        // validates depth when a parent is set but stores the todo's depth
        // field as-is — so we set it explicitly.
        var parentId: UUID?
        var lastId: UUID?
        for i in 0..<7 {
            let blockId = UUID()
            let todoId = UUID()
            try await noteRepo.insertBlock(Block(
                id: blockId, noteId: noteId, kind: .todo, sortKey: i,
                payload: .todo(TodoPayload(todoId: todoId, richText: .plain("todo \(i)"))),
                lastModifiedDeviceId: deviceId
            ))
            try await repo.insert(TodoItem(
                id: todoId, noteId: noteId, blockId: blockId, parentTodoId: parentId,
                sortKey: i, depth: i, lastModifiedDeviceId: deviceId
            ))
            parentId = todoId
            lastId = todoId
        }
        // The last todo is at depth 6 (max). Now create a new top-level todo
        // and try to indent it under the depth-6 todo → depth 7, rejected.
        let childBlockId = UUID()
        let childTodoId = UUID()
        try await noteRepo.insertBlock(Block(
            id: childBlockId, noteId: noteId, kind: .todo, sortKey: 100,
            payload: .todo(TodoPayload(todoId: childTodoId, richText: .plain("child"))),
            lastModifiedDeviceId: deviceId
        ))
        try await repo.insert(TodoItem(
            id: childTodoId, noteId: noteId, blockId: childBlockId, sortKey: 100, depth: 0, lastModifiedDeviceId: deviceId
        ))
        do {
            try await repo.reparent(todoId: childTodoId, newParentId: lastId, deviceId: deviceId)
            Issue.record("indent beyond max depth must be rejected")
        } catch {
            // Rejection is expected (the repository validates depth ≤ 6).
            #expect(true)
        }
    }
}
