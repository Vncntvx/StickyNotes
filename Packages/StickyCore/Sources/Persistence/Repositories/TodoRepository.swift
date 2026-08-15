import Foundation
import GRDB
import Domain

// MARK: - SQLiteTodoRepository (T061)
//
// Per tasks.md T061 and data-model.md §TodoItem:
// - Stable UUID per todo (FR-071) — identity is separate from text.
// - Hierarchy explicit (parent-child), not whitespace-inferred.
// - Validation: no cycles; parent must be in the same note; depth ≤ maxDepth;
//   sort-key collisions normalize; deleting a parent reparents children to
//   grandparent (no orphaned children).
// - Completion/incomplete, reorder, indent/outdent.
//
// The TodoItem's text lives in the block's rich-text payload (TodoPayload);
// this repository owns only the identity/hierarchy/sort/completion fields.

public final class SQLiteTodoRepository: TodoRepository, Sendable {
    private let store: DatabaseStore

    public init(store: DatabaseStore) {
        self.store = store
    }

    // MARK: - Read

    public func fetchTodos(noteId: UUID) async throws -> [TodoItem] {
        try await store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM todoItem WHERE noteId = ? ORDER BY sortKey ASC",
                arguments: [noteId.uuidString]
            )
            return rows.compactMap { try? self.todoFromRow($0) }
        }
    }

    public func fetchTodo(blockId: UUID) async throws -> TodoItem? {
        try await store.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM todoItem WHERE blockId = ?",
                arguments: [blockId.uuidString]
            ) else { return nil }
            return try self.todoFromRow(row)
        }
    }

    // MARK: - Insert

    public func insert(_ todo: TodoItem) async throws {
        try await store.write { db in
            // Validate hierarchy if a parent is set.
            if let parentId = todo.parentTodoId {
                try self.validateParent(parentId, inNote: todo.noteId, db: db)
                if try self.wouldCreateCycle(child: todo.id, candidateParent: parentId, noteId: todo.noteId, db: db) {
                    throw StickyError.persistence(.invalidPayload)
                }
                let parentDepth: Int = try self.fetchDepth(todoId: parentId, db: db) ?? 0
                let newDepth = TodoHierarchy.depth(
                    ofParent: parentId,
                    parentDepthProvider: { _ in parentDepth }
                )
                if newDepth > TodoHierarchy.maxDepth {
                    throw StickyError.persistence(.invalidPayload)
                }
            }
            try self.insertRow(db, todo: todo)
        }
    }

    // MARK: - Update completion

    public func setComplete(todoId: UUID, isComplete: Bool, deviceId: UUID) async throws {
        try await store.write { db in
            try db.execute(
                sql: """
                    UPDATE todoItem
                    SET isComplete = ?,
                        versionId = ?,
                        parentVersionId = (SELECT versionId FROM todoItem WHERE id = ?),
                        lastModifiedDeviceId = ?,
                        modifiedAt = ?
                    WHERE id = ?
                    """,
                arguments: [isComplete, UUID().uuidString, todoId.uuidString, deviceId.uuidString, Date(), todoId.uuidString]
            )
        }
    }

    // MARK: - Reorder

    public func reorder(todoId: UUID, newSortKey: Int, deviceId: UUID) async throws {
        try await store.write { db in
            try db.execute(
                sql: """
                    UPDATE todoItem
                    SET sortKey = ?,
                        versionId = ?,
                        parentVersionId = (SELECT versionId FROM todoItem WHERE id = ?),
                        lastModifiedDeviceId = ?,
                        modifiedAt = ?
                    WHERE id = ?
                    """,
                arguments: [newSortKey, UUID().uuidString, todoId.uuidString, deviceId.uuidString, Date(), todoId.uuidString]
            )
        }
    }

    // MARK: - Reparent (indent/outdent)

    public func reparent(todoId: UUID, newParentId: UUID?, deviceId: UUID) async throws {
        try await store.write { db in
            // Fetch the todo's noteId (needed for parent validation).
            guard let noteIdString: String = try String.fetchOne(
                db,
                sql: "SELECT noteId FROM todoItem WHERE id = ?",
                arguments: [todoId.uuidString]
            ), let noteId = UUID(uuidString: noteIdString) else {
                throw StickyError.persistence(.recordNotFound)
            }

            let newDepth: Int
            if let parentId = newParentId {
                try self.validateParent(parentId, inNote: noteId, db: db)
                if try self.wouldCreateCycle(child: todoId, candidateParent: parentId, noteId: noteId, db: db) {
                    throw StickyError.persistence(.invalidPayload)
                }
                let parentDepth: Int = try self.fetchDepth(todoId: parentId, db: db) ?? 0
                newDepth = TodoHierarchy.depth(
                    ofParent: parentId,
                    parentDepthProvider: { _ in parentDepth }
                )
                if newDepth > TodoHierarchy.maxDepth {
                    throw StickyError.persistence(.invalidPayload)
                }
            } else {
                newDepth = 0
            }

            try db.execute(
                sql: """
                    UPDATE todoItem
                    SET parentTodoId = ?,
                        depth = ?,
                        versionId = ?,
                        parentVersionId = (SELECT versionId FROM todoItem WHERE id = ?),
                        lastModifiedDeviceId = ?,
                        modifiedAt = ?
                    WHERE id = ?
                    """,
                arguments: [newParentId?.uuidString, newDepth, UUID().uuidString, todoId.uuidString, deviceId.uuidString, Date(), todoId.uuidString]
            )
        }
    }

    // MARK: - Delete (reparent children to grandparent)

    public func delete(id: UUID) async throws {
        try await store.write { db in
            // The todo being deleted.
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT noteId, parentTodoId FROM todoItem WHERE id = ?",
                arguments: [id.uuidString]
            ) else {
                throw StickyError.persistence(.recordNotFound)
            }
            let parentIdString: String? = row["parentTodoId"]
            let grandparentId: UUID? = parentIdString.flatMap { UUID(uuidString: $0) }

            // Reparent direct children to the grandparent. Children keep
            // their depth adjusted by -1 if grandparent is nil (depth 0),
            // or to grandparent.depth + 1.
            let childDepth: Int
            if let gp = grandparentId {
                childDepth = (try self.fetchDepth(todoId: gp, db: db) ?? 0) + 1
            } else {
                childDepth = 0
            }
            try db.execute(
                sql: """
                    UPDATE todoItem
                    SET parentTodoId = ?,
                        depth = ?
                    WHERE parentTodoId = ?
                    """,
                arguments: [grandparentId?.uuidString, childDepth, id.uuidString]
            )

            try db.execute(
                sql: "DELETE FROM todoItem WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - Row mapping

    private func insertRow(_ db: Database, todo: TodoItem) throws {
        try db.execute(
            sql: """
                INSERT INTO todoItem (
                    id, noteId, blockId, parentTodoId, sortKey, depth, isComplete,
                    versionId, parentVersionId, lastModifiedDeviceId, createdAt, modifiedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                todo.id.uuidString,
                todo.noteId.uuidString,
                todo.blockId.uuidString,
                todo.parentTodoId?.uuidString,
                todo.sortKey,
                todo.depth,
                todo.isComplete,
                todo.versionId.uuidString,
                todo.parentVersionId?.uuidString,
                todo.lastModifiedDeviceId.uuidString,
                todo.createdAt,
                todo.modifiedAt,
            ]
        )
    }

    private func todoFromRow(_ row: Row) throws -> TodoItem {
        TodoItem(
            id: UUID(uuidString: row["id"] ?? "") ?? UUID(),
            noteId: UUID(uuidString: row["noteId"] ?? "") ?? UUID(),
            blockId: UUID(uuidString: row["blockId"] ?? "") ?? UUID(),
            parentTodoId: (row["parentTodoId"] as String?).flatMap { UUID(uuidString: $0) },
            sortKey: row["sortKey"] ?? 0,
            depth: row["depth"] ?? 0,
            isComplete: row["isComplete"] ?? false,
            versionId: UUID(uuidString: row["versionId"] ?? "") ?? UUID(),
            parentVersionId: (row["parentVersionId"] as String?).flatMap { UUID(uuidString: $0) },
            lastModifiedDeviceId: UUID(uuidString: row["lastModifiedDeviceId"] ?? "") ?? UUID(),
            createdAt: row["createdAt"] ?? Date(),
            modifiedAt: row["modifiedAt"] ?? Date()
        )
    }

    // MARK: - Hierarchy validation helpers

    /// Validates that the parent exists and is in the same note.
    private func validateParent(_ parentId: UUID, inNote noteId: UUID, db: Database) throws {
        let parentNoteId: String? = try String.fetchOne(
            db,
            sql: "SELECT noteId FROM todoItem WHERE id = ?",
            arguments: [parentId.uuidString]
        )
        guard let parentNoteId, let parentUUID = UUID(uuidString: parentNoteId) else {
            throw StickyError.persistence(.recordNotFound)
        }
        guard parentUUID == noteId else {
            throw StickyError.persistence(.invalidPayload)
        }
    }

    /// Returns `true` if making `candidateParent` the parent of `child`
    /// would create a cycle. Feeds the existing parent chain into the
    /// Domain rule (`TodoHierarchy.wouldCreateCycle`) — the traversal
    /// semantics are single-sourced in Domain (R3.5, A-5).
    private func wouldCreateCycle(child: UUID, candidateParent: UUID, noteId: UUID, db: Database) throws -> Bool {
        // Build the parentOf map lazily as the Domain rule walks the chain.
        var parentOf: [UUID: UUID?] = [:]
        var current: UUID? = candidateParent
        var steps = 0
        while let id = current {
            let next: String? = try String.fetchOne(
                db,
                sql: "SELECT parentTodoId FROM todoItem WHERE id = ?",
                arguments: [id.uuidString]
            )
            parentOf[id] = next.flatMap { UUID(uuidString: $0) }
            current = parentOf[id] ?? nil
            steps += 1
            if steps > 1024 { break }  // defensive against corrupt chains
        }
        return TodoHierarchy.wouldCreateCycle(
            child: child,
            candidateParent: candidateParent,
            parentOf: parentOf
        )
    }

    /// Fetches the depth of a todo.
    private func fetchDepth(todoId: UUID, db: Database) throws -> Int? {
        try Int.fetchOne(
            db,
            sql: "SELECT depth FROM todoItem WHERE id = ?",
            arguments: [todoId.uuidString]
        )
    }
}
