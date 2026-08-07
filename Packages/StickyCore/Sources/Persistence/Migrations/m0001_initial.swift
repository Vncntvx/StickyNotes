import Foundation
import GRDB
import Domain

// MARK: - Initial schema migration v1 (T019)
//
// Per data-model.md §Entities and §Indexes. All entities from the data
// model are created here in their v1 form. Future migrations are
// `m0002_*.swift`, `m0003_*.swift`, etc., and each ships with a fixture
// database under `Tests/PersistenceTests/Fixtures/schema_vN.sqlite`.
//
// The `schema_migrations` tracking table is owned by GRDB
// (`grdb_migrations`); we do not create our own. The widget queries the
// latest applied migration name to detect unsupported schemas (research.md
// R6).

// MARK: - Migration identifiers

public enum StickyMigrationId {
    public static let v1 = "v1_initial_schema"
}

// MARK: - The v1 migrator

/// Builds the v1 `DatabaseMigrator` with the initial schema. The main app
/// calls `.migrate(dbPool)` at startup; the widget calls
/// `StickyMigrator.currentSchemaVersion` and falls back to privacy-safe
/// placeholders on mismatch.
public enum InitialSchema {
    public static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // Speed up dev iterations: nuke the DB if a migration's body
        // changes. NEVER enabled in release (data-loss risk; constitution IV).
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration(StickyMigrationId.v1) { db in
            try createV1Schema(in: db)
        }

        return migrator
    }

    /// Creates the v1 schema: all entities, constraints, and indexes from
    /// data-model.md.
    public static func createV1Schema(in db: Database) throws {
        // MARK: Note
        //
        // Created via raw SQL (not GRDB's `db.create(table:)` DSL) so the
        // `coverScreenshotBlockId → block.id` foreign key can be declared
        // `DEFERRABLE INITIALLY DEFERRED`. This defers SQLite's FK target
        // existence check until the first transaction commit, which lets
        // us reference `block` (created below) without reordering. The FK
        // enforces `ON DELETE SET NULL` at the DB level — defense-in-depth
        // alongside the app-layer clearing in NoteRepository.deleteBlock
        // (T030). Per T152 (convergence) and data-model.md:277.

        try db.execute(sql: """
            CREATE TABLE note (
                id TEXT NOT NULL PRIMARY KEY,
                title TEXT,
                colorKey TEXT NOT NULL,
                customColor TEXT,
                transparency DOUBLE NOT NULL,
                textSize TEXT NOT NULL,
                alwaysOnTop BOOLEAN NOT NULL,
                widgetEligible BOOLEAN NOT NULL,
                coverScreenshotBlockId TEXT REFERENCES block(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
                manualSortKey INTEGER NOT NULL,
                lifecycleState TEXT NOT NULL,
                trashedAt DATETIME,
                conflictOriginNoteId TEXT,
                conflictLabel TEXT,
                versionId TEXT NOT NULL,
                parentVersionId TEXT,
                lastModifiedDeviceId TEXT NOT NULL,
                createdAt DATETIME NOT NULL,
                modifiedAt DATETIME NOT NULL
            )
            """)

        // Indexes per data-model.md §Indexes.
        try db.create(index: "note_lifecycle_modifiedAt", on: "note", columns: ["lifecycleState", "modifiedAt"])
        try db.create(index: "note_lifecycle_createdAt", on: "note", columns: ["lifecycleState", "createdAt"])
        try db.create(index: "note_lifecycle_title", on: "note", columns: ["lifecycleState", "title"])
        try db.create(index: "note_lifecycle_manualSortKey", on: "note", columns: ["lifecycleState", "manualSortKey"])
        try db.create(index: "note_lastModifiedDeviceId", on: "note", columns: ["lastModifiedDeviceId"])

        // MARK: Block

        try db.create(table: "block") { t in
            t.column("id", .text).notNull().primaryKey()
            t.column("noteId", .text).notNull()
                .references("note", onDelete: .cascade)
            t.column("kind", .text).notNull()
            t.column("sortKey", .integer).notNull()
            // The payload is canonical JSON (T015/T016). Stored as TEXT.
            t.column("payload", .text).notNull()
            t.column("versionId", .text).notNull()
            t.column("parentVersionId", .text)
            t.column("lastModifiedDeviceId", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("modifiedAt", .datetime).notNull()
        }
        try db.create(index: "block_noteId_sortKey", on: "block", columns: ["noteId", "sortKey"])

        // MARK: TodoItem

        try db.create(table: "todoItem") { t in
            t.column("id", .text).notNull().primaryKey()
            t.column("noteId", .text).notNull()
                .references("note", onDelete: .cascade)
            t.column("blockId", .text).notNull()
                .references("block", onDelete: .cascade)
            t.column("parentTodoId", .text)
            t.column("sortKey", .integer).notNull()
            t.column("depth", .integer).notNull()
            t.column("isComplete", .boolean).notNull()
            t.column("versionId", .text).notNull()
            t.column("parentVersionId", .text)
            t.column("lastModifiedDeviceId", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("modifiedAt", .datetime).notNull()
        }
        try db.create(index: "todoItem_noteId_sortKey", on: "todoItem", columns: ["noteId", "sortKey"])
        try db.create(index: "todoItem_parentTodoId", on: "todoItem", columns: ["parentTodoId"])

        // MARK: Asset

        try db.create(table: "asset") { t in
            t.column("id", .text).notNull().primaryKey()
            t.column("kind", .text).notNull()
            t.column("contentHash", .text).notNull()
            t.column("byteSize", .integer).notNull()
            t.column("contentType", .text).notNull()
            // Device-local only — NEVER in canonical JSON.
            t.column("storagePath", .text).notNull()
            t.column("isSynced", .boolean).notNull().defaults(to: false)
            t.column("syncFailureState", .text).notNull().defaults(to: "none")
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(index: "asset_contentHash", on: "asset", columns: ["contentHash"])
        // Unique constraint enables dedup: identical contentHash among same
        // kind+contentType reuses an existing asset row (data-model.md
        // §Asset; research.md R8 reference counting).
        try db.create(
            index: "asset_kind_contentType_contentHash_unique",
            on: "asset",
            columns: ["kind", "contentType", "contentHash"],
            unique: true
        )

        // MARK: ScreenshotAssociation

        try db.create(table: "screenshotAssociation") { t in
            t.column("blockId", .text).notNull()
                .references("block", onDelete: .cascade)
            t.column("noteId", .text).notNull()
                .references("note", onDelete: .cascade)
            t.column("originalAssetId", .text).notNull()
                .references("asset", onDelete: .restrict)
            t.column("thumbnailAssetId", .text).notNull()
                .references("asset", onDelete: .restrict)
            t.column("appIconAssetId", .text)
                .references("asset", onDelete: .setNull)
            t.column("applicationName", .text)
            t.column("windowTitle", .text)
            t.column("caption", .text)
            t.column("capturedAt", .datetime).notNull()
            t.column("isCover", .boolean).notNull().defaults(to: false)
            // Composite PK — one row per screenshot block.
            t.primaryKey(["blockId"])
        }

        // MARK: FileReference (synced metadata) + FileLocator (device-local)

        try db.create(table: "fileReference") { t in
            t.column("blockId", .text).notNull()
                .references("block", onDelete: .cascade)
            t.column("displayName", .text).notNull()
            t.column("contentType", .text).notNull()
            t.column("approximateSize", .integer)
            t.column("originDeviceId", .text).notNull()
            t.column("addedAt", .datetime).notNull()
            t.column("caption", .text)
            t.primaryKey(["blockId"])
        }

        try db.create(table: "fileLocator") { t in
            // Device-local — NEVER synchronized.
            t.column("blockId", .text).notNull()
                .references("block", onDelete: .cascade)
            t.column("bookmarkData", .blob).notNull()
            t.column("lastResolvedPath", .text).notNull()
            t.column("availabilityStatus", .text).notNull()
            t.column("stale", .boolean).notNull()
            t.column("verifiedAt", .datetime)
            t.primaryKey(["blockId"])
        }

        // MARK: WindowState (device-local)

        try db.create(table: "windowState") { t in
            // Device-local — NEVER synchronized.
            t.column("noteId", .text).notNull()
                .references("note", onDelete: .cascade)
            t.column("frame", .text).notNull()  // JSON {x,y,w,h}
            t.column("preferredDisplayUUID", .text)
            t.column("fallbackFrame", .text)
            t.column("isOpen", .boolean).notNull().defaults(to: false)
            t.column("lastOpenedAt", .datetime)
            t.primaryKey(["noteId"])
        }

        // MARK: Tombstone

        try db.create(table: "tombstone") { t in
            t.column("noteId", .text).notNull()
                .references("note", onDelete: .cascade)
            t.column("deletedVersionId", .text).notNull()
            t.column("parentVersionId", .text)
            t.column("deletingDeviceId", .text).notNull()
            t.column("deletedAt", .datetime).notNull()
            t.column("purgedAt", .datetime)
            t.column("canPurgeRemote", .boolean).notNull().defaults(to: false)
            t.primaryKey(["noteId"])
        }
        try db.create(index: "tombstone_deletedAt", on: "tombstone", columns: ["deletedAt"])

        // MARK: SyncState (device-local)

        try db.create(table: "syncState") { t in
            t.column("vaultId", .text).notNull().primaryKey()
            t.column("providerType", .text).notNull()
            t.column("lastSuccessfulSyncAt", .datetime)
            t.column("lastError", .text)
            t.column("inProgress", .boolean).notNull().defaults(to: false)
            t.column("pendingSince", .datetime)
            t.column("config", .text).notNull()  // JSON redacted config
        }

        // MARK: DeviceIdentity

        try db.create(table: "deviceIdentity") { t in
            t.column("id", .text).notNull().primaryKey()
            t.column("displayName", .text).notNull()
            t.column("createdAt", .datetime).notNull()
        }

        // MARK: VaultConfiguration (device-local)

        try db.create(table: "vaultConfiguration") { t in
            t.column("vaultId", .text).notNull().primaryKey()
            t.column("vaultLocator", .text).notNull()
            t.column("providerType", .text).notNull()
            t.column("providerConfig", .text).notNull()  // JSON redacted
            t.column("keychainCredentialRef", .text).notNull()
            // FR-162a (clarified 2026-08-07): remember-unlock lifetime enum
            // stored as text ("disabled" / "enabledUntilLockOrRestart").
            t.column("rememberedUnlock", .text).notNull().defaults(to: "disabled")
            t.column("rememberedUnlockKeychainRef", .text)
            t.column("rememberedUnlockBootTimestamp", .integer)
            // FR-154 (clarified 2026-08-07): prior locator when the
            // repository was replaced (user reference only; prior remote
            // data is NOT auto-deleted).
            t.column("replacedFromVaultLocator", .text)
            t.column("createdAt", .datetime).notNull()
        }

        // MARK: FTS5 notes_fts (T020)
        //
        // External-content FTS5 synchronized with a `note_fts_content`
        // content table. The FTS columns source from multiple tables
        // (Note.title, generated summary, concatenated block payloads), so
        // SearchService writes the `note_fts_content` rows transactionally
        // when a note changes (T042). `synchronize(withTable:)` below links
        // the virtual table to that content table and installs the
        // INSERT/UPDATE/DELETE triggers (created automatically by GRDB) that
        // keep the FTS index in sync with the content table.

        try db.create(table: "note_fts_content") { t in
            t.column("noteId", .text).notNull().primaryKey()
                .references("note", onDelete: .cascade)
            t.column("title", .text).notNull().defaults(to: "")
            t.column("summary", .text).notNull().defaults(to: "")
            t.column("body", .text).notNull().defaults(to: "")
            t.column("todos", .text).notNull().defaults(to: "")
            t.column("code", .text).notNull().defaults(to: "")
            t.column("fileNames", .text).notNull().defaults(to: "")
            t.column("captions", .text).notNull().defaults(to: "")
            t.column("ocr", .text).notNull().defaults(to: "")
        }

        try db.create(virtualTable: "notes_fts", using: FTS5()) { t in
            t.synchronize(withTable: "note_fts_content")
            t.column("title")
            t.column("summary")
            t.column("body")
            t.column("todos")
            t.column("code")
            t.column("fileNames")
            t.column("captions")
            t.column("ocr")
            // Tokenizer: unicode61 with diacritics removed for accent-
            // insensitive matching across Latin/CJK text. CJK characters
            // are tokenized per-Unicode-category by default.
            // (research.md R16 — Unicode normalization & search.)
            t.tokenizer = .unicode61(diacritics: .remove)
        }
    }
}
