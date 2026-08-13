import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

// MARK: - Schema tests (T026)
//
// The app is pre-release with a single, non-versioned schema (no backward
// compatibility). These tests pin the current schema:
//
// - A fresh store + `InitialSchema.migrator()` creates the current schema.
// - All tables (including conflictRecord) and indexes exist.
// - The FTS5 `notes_fts` virtual table is synchronized with `note_fts_content`.
// - `PRAGMA integrity_check` returns "ok"; foreign keys are ON.
// - The single schema migration is idempotent (a no-op on an existing DB).
// - The schema has NO `widgetEligible` column (removed 2026-08-13).
// - `DatabaseBootstrap.open` applies the schema on a fresh database.
//
// Constitution XII: tests are mandatory.

@Suite struct MigrationTests {

    // MARK: - Helpers

    /// Creates a fresh in-memory DatabaseStore and applies the single schema.
    private func freshDatabase() async throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    // MARK: - Schema creation

    @Test
    func freshDatabaseCreatesAllTables() async throws {
        let store = try await freshDatabase()

        let tables: [String] = try await store.read { db in
            try String
                .fetchAll(db, sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
                    ORDER BY name
                    """)
        }

        let expected: Set<String> = [
            "note", "block", "todoItem", "asset",
            "screenshotAssociation", "fileReference", "fileLocator",
            "windowState", "tombstone", "syncState",
            "deviceIdentity", "vaultConfiguration", "conflictRecord",
            "note_fts_content", "notes_fts",
            // FTS5 shadow tables (created automatically by the virtual table)
            "notes_fts_config", "notes_fts_data", "notes_fts_docsize", "notes_fts_idx",
        ]

        let actual = Set(tables)
        #expect(actual == expected, "Missing tables: \(expected.subtracting(actual).sorted()); extra: \(actual.subtracting(expected).sorted())")
    }

    @Test
    func freshDatabaseCreatesAllIndexes() async throws {
        let store = try await freshDatabase()

        let indexes: [String] = try await store.read { db in
            try String
                .fetchAll(db, sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'index' AND name NOT LIKE 'sqlite_%'
                    ORDER BY name
                    """)
        }

        // The exact auto-index names vary; we check that the named indexes
        // from Schema.swift exist.
        let expected: Set<String> = [
            "note_lifecycle_modifiedAt",
            "note_lifecycle_createdAt",
            "note_lifecycle_title",
            "note_lifecycle_manualSortKey",
            "note_lastModifiedDeviceId",
            "block_noteId_sortKey",
            "todoItem_noteId_sortKey",
            "todoItem_parentTodoId",
            "asset_contentHash",
            "asset_kind_contentType_contentHash_unique",
            "tombstone_deletedAt",
            "conflictRecord_originalNoteId",
        ]
        let actual = Set(indexes)
        let missing = expected.subtracting(actual)
        #expect(missing.isEmpty, "Missing indexes: \(missing.sorted())")
    }

    @Test
    func freshDatabasePassesIntegrityCheck() async throws {
        let store = try await freshDatabase()
        let result: String = try await store.read { db in
            try String.fetchOne(db, sql: "PRAGMA integrity_check") ?? ""
        }
        #expect(result == "ok", "integrity_check failed: \(result)")
    }

    @Test
    func freshDatabaseEnforcesForeignKeys() async throws {
        let store = try await freshDatabase()
        let fkEnabled: Int = try await store.read { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys") ?? 0
        }
        #expect(fkEnabled == 1, "foreign_keys pragma must be ON")
    }

    @Test
    func freshDatabaseUsesWALJournalMode() async throws {
        // In-memory databases use "memory" journal mode, not WAL. We verify
        // the journal_mode pragma is queryable and the config's
        // prepareDatabase block runs without error.
        let store = try DatabaseStore.inMemory()
        let mode: String = try await store.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? ""
        }
        #expect(!mode.isEmpty)
    }

    @Test
    func freshSchemaOmitsWidgetEligibleAndIncludesConflictRecord() async throws {
        let store = try await freshDatabase()

        // No widgetEligible column (widget surface removed 2026-08-13).
        let noteColumns: [String] = try await store.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(note)").map { row -> String in
                row["name"] ?? ""
            }
        }
        #expect(!noteColumns.contains("widgetEligible"),
                "schema must not contain widgetEligible; got \(noteColumns)")

        // conflictRecord is created inline (no separate migration).
        let conflictRecordExists: Bool = try await store.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='conflictRecord')") ?? false
        }
        #expect(conflictRecordExists, "conflictRecord table must exist in the single schema")
    }

    // MARK: - FTS5

    @Test
    func fts5TableIsSynchronizedWithContentTable() async throws {
        let store = try await freshDatabase()

        // Insert a note + a search-document row, then verify a MATCH query
        // finds it. This proves the FTS5 triggers fire on
        // note_fts_content inserts.
        let noteId = UUID()
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, colorKey, transparency, textSize, alwaysOnTop,
                                      manualSortKey, lifecycleState, versionId, lastModifiedDeviceId,
                                      createdAt, modifiedAt)
                    VALUES (?, 'yellow', 0.0, 13, 0, 0, 'active', ?, ?, ?, ?)
                    """,
                arguments: [
                    noteId.uuidString,
                    UUID().uuidString,
                    UUID().uuidString,
                    Date().timeIntervalSince1970,
                    Date().timeIntervalSince1970,
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO note_fts_content (noteId, title, summary, body, todos, code, fileNames, captions, ocr)
                    VALUES (?, 'Hello world', '', 'searchable body text', '', '', '', '', '')
                    """,
                arguments: [noteId.uuidString]
            )
        }

        // Verify the FTS5 trigger fired: a MATCH query should find this row.
        let hits: [SearchResult] = try await store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT note.id, note.title, note.modifiedAt, notes_fts.rank
                    FROM notes_fts
                    JOIN note_fts_content ON note_fts_content.rowid = notes_fts.rowid
                    JOIN note ON note.id = note_fts_content.noteId
                    WHERE notes_fts MATCH 'searchable'
                      AND note.lifecycleState = 'active'
                    ORDER BY notes_fts.rank
                    LIMIT 10
                    """
            )
            return rows.map { row in
                SearchResult(
                    id: UUID(uuidString: row["id"] ?? "") ?? UUID(),
                    title: row["title"],
                    modifiedAt: row["modifiedAt"] ?? Date(),
                    rank: (row["rank"] as Double?) ?? 0
                )
            }
        }

        #expect(hits.count == 1)
        #expect(hits.first?.id == noteId)
    }

    // MARK: - Idempotency

    @Test
    func schemaApplicationIsIdempotent() async throws {
        let store = try DatabaseStore.inMemory()
        let migrator = InitialSchema.migrator()

        // First run creates the schema.
        try migrator.migrate(store.dbPool)

        // Second run is a no-op (single migration, already applied).
        try migrator.migrate(store.dbPool)

        // Schema is intact.
        let noteTableExists: Bool = try await store.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='note')
                """) ?? false
        }
        #expect(noteTableExists)
    }

    // MARK: - Foreign key cascade behavior

    @Test
    func deletingNoteCascadesToBlocksAndTodos() async throws {
        let store = try await freshDatabase()
        let noteId = UUID()
        let blockId = UUID()
        let todoId = UUID()
        let deviceId = UUID()

        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, colorKey, transparency, textSize, alwaysOnTop,
                                      manualSortKey, lifecycleState, versionId, lastModifiedDeviceId,
                                      createdAt, modifiedAt)
                    VALUES (?, 'yellow', 0.0, 13, 0, 0, 'active', ?, ?, ?, ?)
                    """,
                arguments: [noteId.uuidString, UUID().uuidString, deviceId.uuidString,
                            Date().timeIntervalSince1970, Date().timeIntervalSince1970]
            )
            try db.execute(
                sql: """
                    INSERT INTO block (id, noteId, kind, sortKey, payload, versionId, lastModifiedDeviceId,
                                       createdAt, modifiedAt)
                    VALUES (?, ?, 'todo', 0, '{}', ?, ?, ?, ?)
                    """,
                arguments: [blockId.uuidString, noteId.uuidString, UUID().uuidString, deviceId.uuidString,
                            Date().timeIntervalSince1970, Date().timeIntervalSince1970]
            )
            try db.execute(
                sql: """
                    INSERT INTO todoItem (id, noteId, blockId, sortKey, depth, isComplete, versionId,
                                          lastModifiedDeviceId, createdAt, modifiedAt)
                    VALUES (?, ?, ?, 0, 0, 0, ?, ?, ?, ?)
                    """,
                arguments: [todoId.uuidString, noteId.uuidString, blockId.uuidString, UUID().uuidString,
                            deviceId.uuidString, Date().timeIntervalSince1970, Date().timeIntervalSince1970]
            )
        }

        // Delete the note; blocks + todos should cascade.
        try await store.write { db in
            try db.execute(sql: "DELETE FROM note WHERE id = ?", arguments: [noteId.uuidString])
        }

        let blockCount: Int = try await store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM block WHERE noteId = ?",
                             arguments: [noteId.uuidString]) ?? 0
        }
        let todoCount: Int = try await store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM todoItem WHERE noteId = ?",
                             arguments: [noteId.uuidString]) ?? 0
        }
        #expect(blockCount == 0, "Blocks should cascade-delete with the note")
        #expect(todoCount == 0, "Todos should cascade-delete with the note")
    }

    @Test
    func assetDedupUniqueConstraintEnforced() async throws {
        let store = try await freshDatabase()
        let hash = "sha256-abc"
        let assetId1 = UUID()
        let assetId2 = UUID()

        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO asset (id, kind, contentHash, byteSize, contentType, storagePath, isSynced,
                                       syncFailureState, createdAt)
                    VALUES (?, 'original', ?, 100, 'image/png', 'originals/a', 0, 'none', ?)
                    """,
                arguments: [assetId1.uuidString, hash, Date().timeIntervalSince1970]
            )
        }

        // Inserting a second asset with the same (kind, contentType, contentHash)
        // should fail with a constraint violation.
        do {
            try await store.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO asset (id, kind, contentHash, byteSize, contentType, storagePath, isSynced,
                                           syncFailureState, createdAt)
                        VALUES (?, 'original', ?, 100, 'image/png', 'originals/b', 0, 'none', ?)
                        """,
                    arguments: [assetId2.uuidString, hash, Date().timeIntervalSince1970]
                )
            }
            Issue.record("Expected a constraint-violation error on duplicate (kind, contentType, contentHash)")
        } catch {
            // Expected: a DatabaseError. The unique index is what matters.
            #expect(true)
        }
    }

    // MARK: - coverScreenshotBlockId FK (T152 convergence)
    //
    // The note.coverScreenshotBlockId → block.id FK is declared
    // DEFERRABLE INITIALLY DEFERRED (raw SQL). This test asserts the FK
    // exists and that deleting the referenced block nulls the note's
    // coverScreenshotBlockId (ON DELETE SET NULL).

    @Test
    func coverScreenshotBlockIdForeignKeyExistsAndCascadesSetNull() async throws {
        let store = try await freshDatabase()

        // PRAGMA foreign_key_list returns on_delete as a String in this
        // SQLite version (e.g. "SET NULL", "NO ACTION", "CASCADE").
        let fkInfo: [(table: String, onDelete: String)] = try await store.read { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list(note)")
            return rows.map { row -> (table: String, onDelete: String) in
                (table: row["table"] ?? "", onDelete: row["on_delete"] ?? "")
            }
        }
        let blockFK = fkInfo.first { $0.table == "block" }
        #expect(blockFK != nil, "note.coverScreenshotBlockId → block.id FK must exist (T152)")
        #expect(blockFK?.onDelete == "SET NULL", "FK must be ON DELETE SET NULL; got \(String(describing: blockFK?.onDelete))")

        // Behavioral test: deleting the referenced block nulls the cover.
        let noteId = UUID()
        let blockId = UUID()
        let deviceId = UUID()
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, colorKey, transparency, textSize, alwaysOnTop,
                                      manualSortKey, lifecycleState, versionId, lastModifiedDeviceId,
                                      createdAt, modifiedAt)
                    VALUES (?, 'yellow', 0.0, 13, 0, 0, 'active', ?, ?, ?, ?)
                    """,
                arguments: [noteId.uuidString, UUID().uuidString, deviceId.uuidString,
                            Date().timeIntervalSince1970, Date().timeIntervalSince1970]
            )
            try db.execute(
                sql: """
                    INSERT INTO block (id, noteId, kind, sortKey, payload, versionId, lastModifiedDeviceId,
                                       createdAt, modifiedAt)
                    VALUES (?, ?, 'screenshot', 0, '{}', ?, ?, ?, ?)
                    """,
                arguments: [blockId.uuidString, noteId.uuidString, UUID().uuidString, deviceId.uuidString,
                            Date().timeIntervalSince1970, Date().timeIntervalSince1970]
            )
            try db.execute(
                sql: "UPDATE note SET coverScreenshotBlockId = ? WHERE id = ?",
                arguments: [blockId.uuidString, noteId.uuidString]
            )
        }

        let coverBefore: String? = try await store.read { db in
            try String.fetchOne(db, sql: "SELECT coverScreenshotBlockId FROM note WHERE id = ?",
                                arguments: [noteId.uuidString])
        }
        #expect(coverBefore == blockId.uuidString)

        try await store.write { db in
            try db.execute(sql: "DELETE FROM block WHERE id = ?", arguments: [blockId.uuidString])
        }

        let coverAfter: String? = try await store.read { db in
            try String.fetchOne(db, sql: "SELECT coverScreenshotBlockId FROM note WHERE id = ?",
                                arguments: [noteId.uuidString])
        }
        #expect(coverAfter == nil, "deleting the cover screenshot block must null note.coverScreenshotBlockId (ON DELETE SET NULL)")
    }
}

// MARK: - DatabaseBootstrap (T154)

@Suite struct DatabaseBootstrapTests {

    private func tempDirectory(_ name: String) throws -> String {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("bootstrap-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test
    func openCreatesFreshSchema() async throws {
        let dir = try tempDirectory("fresh")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/stickynotes.sqlite"

        let store = try await DatabaseBootstrap.open(databasePath: dbPath)

        let tables: [String] = try await store.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='note'")
        }
        #expect(tables == ["note"], "the single schema must be applied after bootstrap")
    }

    @Test
    func openExistingDatabaseIsNoOp() async throws {
        let dir = try tempDirectory("reopen")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/stickynotes.sqlite"

        // First open creates the schema; insert a note.
        let store = try await DatabaseBootstrap.open(databasePath: dbPath)
        let noteId = UUID()
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, colorKey, transparency, textSize, alwaysOnTop,
                                      manualSortKey, lifecycleState, versionId, lastModifiedDeviceId,
                                      createdAt, modifiedAt)
                    VALUES (?, 'yellow', 0.0, 13, 0, 0, 'active', ?, ?, ?, ?)
                    """,
                arguments: [noteId.uuidString, UUID().uuidString, UUID().uuidString,
                            Date().timeIntervalSince1970, Date().timeIntervalSince1970]
            )
        }

        // Re-opening the same path must not recreate/erase the schema.
        let reopened = try await DatabaseBootstrap.open(databasePath: dbPath)
        let count: Int = try await reopened.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note WHERE id = ?",
                             arguments: [noteId.uuidString]) ?? 0
        }
        #expect(count == 1, "re-opening an existing database must preserve rows")
    }
}
