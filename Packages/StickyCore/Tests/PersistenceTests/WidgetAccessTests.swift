import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

// MARK: - Widget access tests (T094)
//
// Per tasks.md T094: "Persistence test: widget reads App Group SQLite in
// short transactions; todo update atomic; schema-mismatch fallback without
// crash".

@Suite struct WidgetAccessTests {

    private func widgetStore() throws -> DatabaseStore {
        // Widget-like: short busy timeout; migration run by the "app" first.
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    private func insertNote(_ store: DatabaseStore, noteId: UUID) async throws {
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, colorKey, transparency, textSize, alwaysOnTop, widgetEligible,
                                      manualSortKey, lifecycleState, versionId, lastModifiedDeviceId,
                                      createdAt, modifiedAt)
                    VALUES (?, 'yellow', 0.0, 13, 0, 1, 0, 'active', ?, ?, ?, ?)
                    """,
                arguments: [noteId.uuidString, UUID().uuidString, UUID().uuidString,
                            Date().timeIntervalSince1970, Date().timeIntervalSince1970]
            )
        }
    }

    private func insertTodo(_ store: DatabaseStore, noteId: UUID, todoId: UUID, text: String, isComplete: Bool = false) async throws {
        let blockId = UUID()
        let payload = TodoPayload(todoId: todoId, richText: .plain(text))
        let payloadJSON = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO block (id, noteId, kind, sortKey, payload, versionId, lastModifiedDeviceId,
                                       createdAt, modifiedAt)
                    VALUES (?, ?, 'todo', 0, ?, ?, ?, ?, ?)
                    """,
                arguments: [blockId.uuidString, noteId.uuidString, payloadJSON, UUID().uuidString,
                            UUID().uuidString, Date().timeIntervalSince1970, Date().timeIntervalSince1970]
            )
            try db.execute(
                sql: """
                    INSERT INTO todoItem (id, noteId, blockId, sortKey, depth, isComplete, versionId,
                                          lastModifiedDeviceId, createdAt, modifiedAt)
                    VALUES (?, ?, ?, 0, 0, ?, ?, ?, ?, ?)
                    """,
                arguments: [todoId.uuidString, noteId.uuidString, blockId.uuidString, isComplete ? 1 : 0,
                            UUID().uuidString, UUID().uuidString, Date().timeIntervalSince1970, Date().timeIntervalSince1970]
            )
        }
    }

    // MARK: - Short reads

    @Test
    func widgetReadsUseShortTransactions() async throws {
        let store = try widgetStore()
        let noteId = UUID()
        try await insertNote(store, noteId: noteId)
        try await insertTodo(store, noteId: noteId, todoId: UUID(), text: "call 张三")

        // Widget-like read: bounded busy timeout, small result set.
        let pool = try WidgetDatabase.openPool(path: store.databasePath ?? "", busyTimeout: 1.0)
        let todos = try WidgetDatabase.fetchTodos(pool: pool, noteId: noteId)
        #expect(todos.count == 1)
        #expect(todos.first?.text == "call 张三")
        #expect(todos.first?.isComplete == false)
    }

    // MARK: - Atomic todo toggle

    @Test
    func todoToggleIsAtomicSingleTransaction() async throws {
        let store = try widgetStore()
        let noteId = UUID()
        let todoId = UUID()
        try await insertNote(store, noteId: noteId)
        try await insertTodo(store, noteId: noteId, todoId: todoId, text: "task", isComplete: false)

        let newState = try WidgetDatabase.toggleTodo(pool: store.dbPool, todoId: todoId)
        #expect(newState == true)

        // State is durable within the same transaction scope.
        let row: Bool? = try await store.dbPool.read { db in
            try Bool.fetchOne(db, sql: "SELECT isComplete FROM todoItem WHERE id = ?",
                              arguments: [todoId.uuidString])
        }
        #expect(row == true)

        // Toggling again reverts.
        let reverted = try WidgetDatabase.toggleTodo(pool: store.dbPool, todoId: todoId)
        #expect(reverted == false)
    }

    @Test
    func togglingMissingTodoIsGracefulNoOp() throws {
        let store = try widgetStore()
        let result = try WidgetDatabase.toggleTodo(pool: store.dbPool, todoId: UUID())
        #expect(result == nil, "a todo deleted between render and tap must not crash or error")
    }

    // MARK: - Schema-mismatch fallback

    @Test
    func schemaMismatchFallsBackWithoutCrash() async throws {
        let store = try widgetStore()

        // Supported schema → supported.
        let supported = await WidgetDatabase.isSchemaSupported(path: store.databasePath ?? "")
        #expect(supported)

        // Unknown/missing schema → unsupported (privacy-safe fallback path),
        // without crashing and without attempting migration.
        let unknownPath = NSTemporaryDirectory() + "widget-unknown-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: unknownPath) }
        let pool = try DatabasePool(path: unknownPath)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v99_unknown_schema") { db in
            try db.create(table: "widget_marker") { $0.column("id", .text) }
        }
        try migrator.migrate(pool)

        let supported99 = await WidgetDatabase.isSchemaSupported(path: unknownPath)
        #expect(!supported99, "unknown schema version must report unsupported")

        // Missing DB file → unsupported (no crash).
        let missing = await WidgetDatabase.isSchemaSupported(
            path: NSTemporaryDirectory() + "widget-missing-\(UUID().uuidString).sqlite"
        )
        #expect(!missing)
    }
}
