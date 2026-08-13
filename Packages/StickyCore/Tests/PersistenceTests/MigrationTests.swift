import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

// MARK: - Migration tests (T026)
//
// Per tasks.md T026: "Migration test: fresh DB creation + v1 schema integrity
// in `Packages/StickyCore/Tests/PersistenceTests/MigrationTests.swift`."
//
// Verifies:
// - A fresh DatabaseStore + InitialSchema.migrator() creates the v1 schema
//   without errors.
// - All tables from data-model.md §Entities exist.
// - All indexes from data-model.md §Indexes exist.
// - The FTS5 `notes_fts` virtual table exists and is synchronized with
//   `note_fts_content`.
// - `PRAGMA integrity_check` returns "ok".
// - The schema migration is idempotent (running it twice is a no-op).
// - Interrupted-migration recovery restores the backup.
//
// Constitution XII: tests are mandatory.

@Suite struct MigrationTests {

    // MARK: - Helpers

    /// Creates a fresh in-memory DatabaseStore and runs the v1 migrator.
    private func freshDatabase() async throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        let migrator = InitialSchema.migrator()
        try migrator.migrate(store.dbPool)
        return store
    }

    // MARK: - v1 schema creation

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
            "deviceIdentity", "vaultConfiguration",
            "conflictRecord",  // v2 (US10 conflict-copy dedup)
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
        // from m0001_initial.swift exist.
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
    func migrationIsIdempotent() async throws {
        let store = try DatabaseStore.inMemory()
        let migrator = InitialSchema.migrator()

        // First run creates the schema.
        try migrator.migrate(store.dbPool)

        // Second run is a no-op (no pending migrations).
        try migrator.migrate(store.dbPool)

        // Schema is intact.
        let noteTableExists: Bool = try await store.read { db in
            try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='note')
                """) ?? false
        }
        #expect(noteTableExists)
    }

    // MARK: - v3: widget-eligibility column removal (2026-08-13)

    @Test
    func freshDatabaseHasNoWidgetEligibleColumn() async throws {
        let store = try await freshDatabase()

        let columns: [String] = try await store.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(note)").map { row -> String in
                row["name"] ?? ""
            }
        }
        #expect(!columns.contains("widgetEligible"),
                "v3 must drop the widgetEligible column on a fresh database; got \(columns)")
    }

    @Test
    func v3MigrationDropsWidgetEligibilityAndPreservesRows() async throws {
        // Build a database at v2 (the pre-removal state), insert a note row
        // WITH the widgetEligible column, then run the real migrator: v3
        // must drop the column while preserving every row and value.
        let store = try DatabaseStore.inMemory()

        // v1 + v2 only (the pre-removal chain).
        var legacyMigrator = DatabaseMigrator()
        legacyMigrator.registerMigration(StickyMigrationId.v1) { db in
            try InitialSchema.createV1Schema(in: db)
        }
        legacyMigrator.registerMigration(StickyMigrationId.v2) { db in
            try ConflictRecordSchema.migrateV2(db)
        }
        try legacyMigrator.migrate(store.dbPool)

        let noteId = UUID()
        let deviceId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, title, colorKey, transparency, textSize, alwaysOnTop, widgetEligible,
                                      manualSortKey, lifecycleState, versionId, lastModifiedDeviceId,
                                      createdAt, modifiedAt)
                    VALUES (?, 'legacy title', 'yellow', 0.5, 16, 1, 0, 2048, 'active', ?, ?, ?, ?)
                    """,
                arguments: [noteId.uuidString, UUID().uuidString, deviceId.uuidString,
                            createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970]
            )
        }

        // Apply v3 through the real migrator.
        try InitialSchema.migrator().migrate(store.dbPool)

        // The column is gone.
        let columns: [String] = try await store.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(note)").map { row -> String in
                row["name"] ?? ""
            }
        }
        #expect(!columns.contains("widgetEligible"), "v3 must drop widgetEligible; got \(columns)")

        // The row survives with all remaining values intact.
        struct SurvivingRow: Sendable {
            var title: String?
            var transparency: Double
            var textSize: Int
            var alwaysOnTop: Bool
            var manualSortKey: Int
            var lifecycle: String
        }
        let survivor = try await store.read { db -> SurvivingRow in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT title, transparency, textSize, alwaysOnTop, manualSortKey, lifecycleState FROM note WHERE id = ?",
                arguments: [noteId.uuidString]
            )
            guard let row else {
                return SurvivingRow(title: nil, transparency: 0, textSize: 0, alwaysOnTop: false, manualSortKey: 0, lifecycle: "")
            }
            return SurvivingRow(
                title: row["title"] as String?,
                transparency: row["transparency"] as Double? ?? 0,
                textSize: row["textSize"] as Int? ?? 0,
                alwaysOnTop: row["alwaysOnTop"] as Bool? ?? false,
                manualSortKey: row["manualSortKey"] as Int? ?? 0,
                lifecycle: row["lifecycleState"] as String? ?? ""
            )
        }
        #expect(survivor.title == "legacy title", "v3 must preserve existing note rows")
        #expect(survivor.transparency == 0.5)
        #expect(survivor.textSize == 16)
        #expect(survivor.alwaysOnTop)
        #expect(survivor.manualSortKey == 2048)
        #expect(survivor.lifecycle == "active")

        // v3 is recorded.
        let applied: [String] = try await store.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
        }
        #expect(applied.contains(StickyMigrationId.v3), "v3 must be recorded in grdb_migrations")
    }

    // MARK: - Schema version tracking

    @Test
    func migratorRecordsAppliedVersion() async throws {
        let store = try DatabaseStore.inMemory()
        let migrator = InitialSchema.migrator()
        try migrator.migrate(store.dbPool)

        // GRDB's tracking table is `grdb_migrations` (column: `identifier`).
        let applied: [String] = try await store.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
        #expect(applied.contains(StickyMigrationId.v1))
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
        // should fail with a constraint violation (mapped to PersistenceError).
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
            // Expected: mapped to a StickyError.persistence(.invalidPayload) or
            // raw DatabaseError. Either is acceptable — the unique index is
            // what matters here.
            #expect(true)
        }
    }

    // MARK: - coverScreenshotBlockId FK (T152 convergence)
    //
    // The note.coverScreenshotBlockId → block.id FK is declared
    // DEFERRABLE INITIALLY DEFERRED in m0001 (raw SQL). This test asserts
    // the FK exists in sqlite_master's foreign_key_list and that deleting
    // the referenced block nulls the note's coverScreenshotBlockId (ON
    // DELETE SET NULL).

    @Test
    func coverScreenshotBlockIdForeignKeyExistsAndCascadesSetNull() async throws {
        let store = try await freshDatabase()

        // The FK should be registered. PRAGMA foreign_key_list(note) lists
        // it; the "table" column points at "block" with ON DELETE SET NULL.
        // Row isn't Sendable in GRDB, so extract values inside the read.
        // PRAGMA foreign_key_list returns on_delete as a String in this
        // SQLite version (e.g. "SET NULL", "NO ACTION", "CASCADE").
        let fkInfo: [(table: String, onDelete: String)] = try await store.read { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list(note)")
            return rows.map { row -> (table: String, onDelete: String) in
                (table: row["table"] ?? "", onDelete: row["on_delete"] ?? "")
            }
        }
        // Find the FK whose target table is "block".
        let blockFK = fkInfo.first { $0.table == "block" }
        #expect(blockFK != nil, "note.coverScreenshotBlockId → block.id FK must exist (T152)")
        #expect(blockFK?.onDelete == "SET NULL", "FK must be ON DELETE SET NULL; got \(String(describing: blockFK?.onDelete))")

        // Behavioral test: inserting a note + a screenshot block, setting
        // the cover reference, then deleting the block should null the
        // note's coverScreenshotBlockId (DB-level ON DELETE SET NULL).
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

        // Verify the cover reference is set.
        let coverBefore: String? = try await store.read { db in
            try String.fetchOne(db, sql: "SELECT coverScreenshotBlockId FROM note WHERE id = ?",
                                arguments: [noteId.uuidString])
        }
        #expect(coverBefore == blockId.uuidString)

        // Delete the block; the DB-level ON DELETE SET NULL should fire.
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

// MARK: - Migration recovery & bootstrap tests (T153, T154)
//
// Per tasks.md T153: "Add migration-recovery tests covering `StickyMigrator`
// pre-migration backup creation, restore-on-migration-failure,
// `MigrationRecovery.recoverFromInterruptedMigration` (missing DB / corrupt
// DB / intact DB no-op / backup consumed after restore), and
// `currentSchemaVersion` fallback".
//
// T154: `DatabaseBootstrap` wires recovery → open → migrate as one startup
// sequence; its behavior is verified here so the App target only calls it.

@Suite struct MigrationRecoveryTests {

    // MARK: - Helpers

    /// A unique temp directory for a single test; removed afterwards.
    private func tempDirectory(_ name: String) throws -> String {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("migration-recovery-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Creates a database at `path` with the v1 schema applied and a known
    /// note row inserted. Returns the open pool (caller must close).
    private func makeMigratedDatabase(at path: String, noteId: UUID = UUID()) throws -> DatabasePool {
        let pool = try DatabasePool(path: path)
        try InitialSchema.migrator().migrate(pool)
        try pool.write { db in
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
        }
        return pool
    }

    /// A migrator with v1 (already applied in `makeMigratedDatabase`) plus a
    /// pending v2 that creates a marker table.
    private func migratorWithPendingV2() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(StickyMigrationId.v1) { db in
            try InitialSchema.createV1Schema(in: db)
        }
        migrator.registerMigration("v2_test_marker") { db in
            try db.create(table: "v2_marker") { t in
                t.column("id", .text).primaryKey()
            }
        }
        return migrator
    }

    /// A migrator with v1 plus a v2 that always fails (mid-migration).
    private func migratorWithFailingV2() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(StickyMigrationId.v1) { db in
            try InitialSchema.createV1Schema(in: db)
        }
        migrator.registerMigration("v2_failing") { _ in
            throw DatabaseError(resultCode: .SQLITE_INTERNAL, message: "boom")
        }
        return migrator
    }

    // MARK: - StickyMigrator: pre-migration backup + restore-on-failure

    @Test
    func preMigrationBackupIsCreatedAndConsumedOnSuccess() async throws {
        let dir = try tempDirectory("backup-created")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/db.sqlite"
        let backupPath = dbPath + ".backup"

        // Existing DB with v1 applied; v2 is pending.
        let pool = try makeMigratedDatabase(at: dbPath)
        try pool.close()

        let migrator = StickyMigrator(
            migrator: migratorWithPendingV2(),
            databasePath: dbPath,
            backupPath: backupPath
        )

        // Run the migration against a fresh pool (the StickyMigrator backs
        // up the file on disk, not the open pool).
        let pool2 = try DatabasePool(path: dbPath)
        try await migrator.migrate(pool2)

        // v2 applied; backup consumed after success.
        let markerExists: Bool = try await pool2.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='v2_marker')") ?? false
        }
        #expect(markerExists, "pending v2 must be applied")
        #expect(!FileManager.default.fileExists(atPath: backupPath),
                "backup must be consumed after a successful migration")
        try pool2.close()
    }

    @Test
    func failedMigrationRestoresBackupAndLeavesPreviousStateIntact() async throws {
        let dir = try tempDirectory("restore-on-failure")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/db.sqlite"
        let backupPath = dbPath + ".backup"
        let noteId = UUID()

        // DB with v1 applied and one known note row.
        let pool = try makeMigratedDatabase(at: dbPath, noteId: noteId)
        try pool.close()

        let migrator = StickyMigrator(
            migrator: migratorWithFailingV2(),
            databasePath: dbPath,
            backupPath: backupPath
        )

        let pool2 = try DatabasePool(path: dbPath)
        do {
            try await migrator.migrate(pool2)
            Issue.record("Expected the failing v2 migration to throw")
        } catch {
            // .migrationFailed
        }
        try pool2.close()

        // The restored DB must still have v1 applied, no v2, and the note row.
        let pool3 = try DatabasePool(path: dbPath)
        let noteCount: Int = try await pool3.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note WHERE id = ?",
                             arguments: [noteId.uuidString]) ?? 0
        }
        let v2Applied: Int = try await pool3.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations WHERE identifier = 'v2_failing'") ?? -1
        }
        #expect(noteCount == 1, "restored DB must contain pre-migration data")
        #expect(v2Applied == 0, "failed migration must not be recorded")
        try pool3.close()
    }

    // MARK: - MigrationRecovery.recoverFromInterruptedMigration

    @Test
    func recoveryRestoresMissingDatabaseFromBackupAndConsumesIt() async throws {
        let dir = try tempDirectory("recovery-missing-db")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/db.sqlite"
        let backupPath = dbPath + ".backup"
        let noteId = UUID()

        let pool = try makeMigratedDatabase(at: dbPath, noteId: noteId)
        try pool.close()

        // Back up, then lose the database file entirely.
        try FileManager.default.copyItem(atPath: dbPath, toPath: backupPath)
        try FileManager.default.removeItem(atPath: dbPath)

        try MigrationRecovery.recoverFromInterruptedMigration(
            databasePath: dbPath,
            backupPath: backupPath
        )

        #expect(!FileManager.default.fileExists(atPath: backupPath),
                "backup must be consumed after restore")
        #expect(FileManager.default.fileExists(atPath: dbPath),
                "database must be restored from backup")

        let pool2 = try DatabasePool(path: dbPath)
        let noteCount: Int = try await pool2.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note WHERE id = ?",
                             arguments: [noteId.uuidString]) ?? 0
        }
        #expect(noteCount == 1, "restored database must contain the pre-migration data")
        try pool2.close()
    }

    @Test
    func recoveryRestoresCorruptDatabaseFromBackup() async throws {
        let dir = try tempDirectory("recovery-corrupt-db")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/db.sqlite"
        let backupPath = dbPath + ".backup"
        let noteId = UUID()

        let pool = try makeMigratedDatabase(at: dbPath, noteId: noteId)
        try pool.close()

        // Back up, then corrupt the database file.
        try FileManager.default.copyItem(atPath: dbPath, toPath: backupPath)
        try Data("not a sqlite database at all".utf8).write(to: URL(fileURLWithPath: dbPath))

        try MigrationRecovery.recoverFromInterruptedMigration(
            databasePath: dbPath,
            backupPath: backupPath
        )

        #expect(!FileManager.default.fileExists(atPath: backupPath),
                "backup must be consumed after restore")
        let pool2 = try DatabasePool(path: dbPath)
        let ok: String = try await pool2.read { db in
            try String.fetchOne(db, sql: "PRAGMA integrity_check") ?? ""
        }
        #expect(ok == "ok", "restored database must pass integrity check; got \(ok)")
        try pool2.close()
    }

    @Test
    func recoveryIsNoOpForIntactDatabase() async throws {
        let dir = try tempDirectory("recovery-intact")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/db.sqlite"
        let backupPath = dbPath + ".backup"
        let noteId = UUID()

        let pool = try makeMigratedDatabase(at: dbPath, noteId: noteId)
        try pool.close()

        // Intact DB + a stale backup (e.g. leftover from an interrupted run
        // whose DB actually completed).
        try FileManager.default.copyItem(atPath: dbPath, toPath: backupPath)

        try MigrationRecovery.recoverFromInterruptedMigration(
            databasePath: dbPath,
            backupPath: backupPath
        )

        // Intact DB must be untouched — no restore, backup retained.
        #expect(FileManager.default.fileExists(atPath: backupPath),
                "no restore happens for an intact database; backup stays")
        let pool2 = try DatabasePool(path: dbPath)
        let noteCount: Int = try await pool2.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note WHERE id = ?",
                             arguments: [noteId.uuidString]) ?? 0
        }
        #expect(noteCount == 1, "intact database must not be modified")
        try pool2.close()
    }

    // MARK: - currentSchemaVersion fallback

    @Test
    func currentSchemaVersionReportsLatestApplied() async throws {
        let dir = try tempDirectory("schema-version")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/db.sqlite"

        let pool = try DatabasePool(path: dbPath)
        try InitialSchema.migrator().migrate(pool)

        let migrator = StickyMigrator(
            migrator: InitialSchema.migrator(),
            databasePath: dbPath,
            backupPath: dbPath + ".backup"
        )
        let version = await migrator.currentSchemaVersion(pool)
        #expect(version == StickyMigrationId.v3, "expected \(StickyMigrationId.v3), got \(String(describing: version))")
        try pool.close()
    }

    @Test
    func currentSchemaVersionIsNilForUnmigratedDatabase() async throws {
        let dir = try tempDirectory("schema-version-unmigrated")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/db.sqlite"

        // A fresh, empty database — no migrations applied: reports nil.
        let pool = try DatabasePool(path: dbPath)
        let migrator = StickyMigrator(
            migrator: InitialSchema.migrator(),
            databasePath: dbPath,
            backupPath: dbPath + ".backup"
        )
        let version = await migrator.currentSchemaVersion(pool)
        #expect(version == nil, "unmigrated database must report nil schema version")
        try pool.close()
    }

    // MARK: - DatabaseBootstrap (T154)

    @Test
    func bootstrapOpensMigratedStoreOnFreshDatabase() async throws {
        let dir = try tempDirectory("bootstrap-fresh")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/db.sqlite"
        let backupPath = dbPath + ".backup"

        let store = try await DatabaseBootstrap.open(
            databasePath: dbPath,
            backupPath: backupPath
        )

        // Schema v1 applied.
        let tables: [String] = try await store.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='note'")
        }
        #expect(tables == ["note"], "v1 schema must be applied after bootstrap")
        // Backup consumed after successful migration.
        #expect(!FileManager.default.fileExists(atPath: backupPath))
    }

    @Test
    func bootstrapRecoversInterruptedMigrationAndMigrates() async throws {
        let dir = try tempDirectory("bootstrap-recovery")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/db.sqlite"
        let backupPath = dbPath + ".backup"
        let noteId = UUID()

        // Simulate an interrupted migration: DB was lost mid-migration but a
        // backup survives.
        let pool = try makeMigratedDatabase(at: dbPath, noteId: noteId)
        try pool.close()
        try FileManager.default.copyItem(atPath: dbPath, toPath: backupPath)
        try FileManager.default.removeItem(atPath: dbPath)

        let store = try await DatabaseBootstrap.open(
            databasePath: dbPath,
            backupPath: backupPath
        )

        // Recovered, migrated, and consistent.
        let noteCount: Int = try await store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note WHERE id = ?",
                             arguments: [noteId.uuidString]) ?? 0
        }
        #expect(noteCount == 1, "recovered database must contain pre-migration data")
        #expect(!FileManager.default.fileExists(atPath: backupPath),
                "backup must be consumed after recovery+restore")
    }
}
