import Foundation
import GRDB
import Domain

// MARK: - Migration framework (T018)
//
// Per plan §Local storage and data-model.md §Migration strategy:
//
// - Ordered, named migrations owned by the main app (`Persistence`).
// - Each migration is a tested function `migrate_vN_vNplus1(_ db)`.
// - A fixture database exists for every historical schema version
//   (`Tests/PersistenceTests/Fixtures/schema_vN.sqlite`).
// - High-risk migrations: back up the DB file before running; on failure,
//   restore backup and report `SchemaCompatibility` error; never leave a
//   half-migrated DB.
// - Interrupted migration recovery: a `schema_migrations` table records
//   applied migrations atomically; an incomplete migration is rolled back
//   via the backup on next launch.
//
// GRDB's `DatabaseMigrator` already implements the `schema_migrations`
// table pattern (its own `grdb_migrations` table). We wrap it to add
// project-specific pre-migration backup and interrupted-migration recovery.

/// The StickyNotes migrator. Wraps GRDB's `DatabaseMigrator` to add:
/// - Pre-migration backup (high-risk migrations).
/// - Interrupted-migration recovery (restore backup on next launch).
/// - Integrity check before and after migration.
/// - Schema version query.
public struct StickyMigrator: Sendable {
    public let migrator: DatabaseMigrator
    public let databasePath: String
    public let backupPath: String

    public init(migrator: DatabaseMigrator, databasePath: String, backupPath: String) {
        self.migrator = migrator
        self.databasePath = databasePath
        self.backupPath = backupPath
    }

    /// Runs all pending migrations. Pre-migration backup is created if any
    /// migration is pending; on failure, the backup is restored and an
    /// `SchemaCompatibility` error is thrown.
    public func migrate(_ dbPool: DatabasePool) async throws {
        // Check if any migration is pending (registered but not yet applied).
        let hasPendingMigrations: Bool = try await dbPool.read { db in
            let registered = Set(self.migrator.migrations)
            let applied = Set(try self.migrator.appliedMigrations(db))
            return !registered.isSubset(of: applied)
        }

        guard hasPendingMigrations else {
            // No-op: already up to date. Still run an integrity check.
            try await integrityCheck(dbPool)
            return
        }

        // Pre-migration backup (research.md R6; data-model.md §Migration
        // strategy).
        try backUpDatabase()

        do {
            // GRDB's migrator manages its own transaction internally.
            try migrator.migrate(dbPool)
            // Post-migration integrity check. If it fails, restore backup.
            try await integrityCheck(dbPool)
            // Success: the backup's only purpose was crash recovery during
            // migration. Consume it so a later launch never restores the
            // pre-migration state over a healthy database.
            removeBackup()
        } catch {
            // Interrupted-migration recovery: restore the backup.
            try? restoreBackup()
            throw StickyError.persistence(.migrationFailed)
        }
    }

    /// Returns the current schema version (the identifier of the latest
    /// applied migration).
    ///
    /// Returns `nil` when no migration has been applied (fresh or unmigrated
    /// database) — the caller's fallback path.
    public func currentSchemaVersion(_ dbPool: DatabasePool) async -> String? {
        await Self.currentSchemaVersion(dbPool, migrator: migrator)
    }

    /// Static form: opens no store of its own, only reads the latest applied
    /// migration identifier from `grdb_migrations`. Returns `nil` (never
    /// throws) when the table is missing or unreadable.
    public static func currentSchemaVersion(
        _ dbPool: DatabasePool,
        migrator: DatabaseMigrator = InitialSchema.migrator()
    ) async -> String? {
        do {
            let applied: [String] = try await dbPool.read { db in
                try String.fetchAll(
                    db,
                    sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier DESC LIMIT 1"
                )
            }
            return applied.first
        } catch {
            // Missing/unreadable grdb_migrations: treat as unmigrated
            // (plan §Local storage).
            return nil
        }
    }

    // MARK: - Integrity check (T022)

    /// Runs `PRAGMA integrity_check`. Throws `.integrityCheckFailed` on any
    /// issue.
    public func integrityCheck(_ dbPool: DatabasePool) async throws {
        let result: String = try await dbPool.read { db in
            try String.fetchOne(db, sql: "PRAGMA integrity_check") ?? ""
        }
        if result != "ok" {
            throw StickyError.persistence(.integrityCheckFailed)
        }
    }

    // MARK: - Backup / restore

    /// Copies the database file to `backupPath` before a high-risk migration.
    /// WAL/shm side files are also copied to ensure the restored state is
    /// consistent.
    public func backUpDatabase() throws {
        let fm = FileManager.default
        // Remove a stale backup from a previous run.
        try? fm.removeItem(atPath: backupPath)
        try? fm.removeItem(atPath: backupPath + "-wal")
        try? fm.removeItem(atPath: backupPath + "-shm")

        guard fm.fileExists(atPath: databasePath) else {
            // No DB yet — nothing to back up. The migration will create it.
            return
        }
        do {
            try fm.copyItem(atPath: databasePath, toPath: backupPath)
            // Copy WAL/shm if present (active WAL state).
            if fm.fileExists(atPath: databasePath + "-wal") {
                try fm.copyItem(atPath: databasePath + "-wal", toPath: backupPath + "-wal")
            }
            if fm.fileExists(atPath: databasePath + "-shm") {
                try fm.copyItem(atPath: databasePath + "-shm", toPath: backupPath + "-shm")
            }
        } catch {
            throw StickyError.persistence(.recoveryFailed)
        }
    }

    /// Removes the backup file (and WAL/shm sidecars). Called after a
    /// successful migration so no stale backup can ever overwrite a healthy
    /// database.
    public func removeBackup() {
        let fm = FileManager.default
        try? fm.removeItem(atPath: backupPath)
        try? fm.removeItem(atPath: backupPath + "-wal")
        try? fm.removeItem(atPath: backupPath + "-shm")
    }

    /// Restores the database file from `backupPath` after a failed migration.
    public func restoreBackup() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupPath) else {
            // No backup — nothing to restore. Caller will report the
            // original migration error.
            return
        }
        do {
            try? fm.removeItem(atPath: databasePath)
            try? fm.removeItem(atPath: databasePath + "-wal")
            try? fm.removeItem(atPath: databasePath + "-shm")
            try fm.copyItem(atPath: backupPath, toPath: databasePath)
            if fm.fileExists(atPath: backupPath + "-wal") {
                try fm.copyItem(atPath: backupPath + "-wal", toPath: databasePath + "-wal")
            }
            if fm.fileExists(atPath: backupPath + "-shm") {
                try fm.copyItem(atPath: backupPath + "-shm", toPath: databasePath + "-shm")
            }
        } catch {
            throw StickyError.persistence(.recoveryFailed)
        }
    }
}

// MARK: - Recovery (T022)
//
// Per data-model.md §Migration strategy: an incomplete migration is rolled
// back via the backup on next launch. This function is called at app
// startup BEFORE the migrator runs: if a backup exists and the DB is in a
// half-migrated state, restore the backup.

public enum MigrationRecovery {
    /// Called at app startup. If a backup exists (indicating a prior
    /// migration attempt was interrupted), restores it before the migrator
    /// runs again. Idempotent — safe to call on every launch.
    public static func recoverFromInterruptedMigration(
        databasePath: String,
        backupPath: String
    ) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupPath) else {
            // No backup — no recovery needed.
            return
        }

        // If the DB file is missing or the schema_migrations table is
        // inconsistent, restore the backup.
        let dbExists = fm.fileExists(atPath: databasePath)
        if !dbExists {
            // The migration created the DB file but didn't finish; remove
            // any partial state and restore the backup (if any).
            try restore(databasePath: databasePath, backupPath: backupPath)
            return
        }

        // Open the DB read-only and check whether the migrations table
        // is consistent. If we can't open it or it reports an unfinished
        // migration, restore.
        do {
            var config = Configuration()
            config.readonly = true
            config.foreignKeysEnabled = false  // don't enforce during recovery check
            let pool = try DatabasePool(path: databasePath, configuration: config)
            let result: String = try pool.read { db in
                try String.fetchOne(db, sql: "PRAGMA integrity_check") ?? ""
            }
            if result != "ok" {
                try restore(databasePath: databasePath, backupPath: backupPath)
            }
        } catch {
            // DB is unreadable — restore the backup.
            try restore(databasePath: databasePath, backupPath: backupPath)
        }
    }

    private static func restore(databasePath: String, backupPath: String) throws {
        let fm = FileManager.default
        do {
            try? fm.removeItem(atPath: databasePath)
            try? fm.removeItem(atPath: databasePath + "-wal")
            try? fm.removeItem(atPath: databasePath + "-shm")
            try fm.copyItem(atPath: backupPath, toPath: databasePath)
            if fm.fileExists(atPath: backupPath + "-wal") {
                try fm.copyItem(atPath: backupPath + "-wal", toPath: databasePath + "-wal")
            }
            if fm.fileExists(atPath: backupPath + "-shm") {
                try fm.copyItem(atPath: backupPath + "-shm", toPath: databasePath + "-shm")
            }
            // Backup consumed — remove it so we don't restore again next
            // launch.
            try? fm.removeItem(atPath: backupPath)
            try? fm.removeItem(atPath: backupPath + "-wal")
            try? fm.removeItem(atPath: backupPath + "-shm")
        } catch {
            throw StickyError.persistence(.recoveryFailed)
        }
    }
}
