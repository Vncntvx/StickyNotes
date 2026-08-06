import Foundation
import GRDB
import Domain

// MARK: - DatabaseBootstrap (T154)
//
// Per plan §Local storage: the main app owns migrations. At startup it must
// (1) recover from any interrupted migration, (2) open the DatabasePool in
// WAL mode, and (3) run pending migrations with a pre-migration backup and
// post-migration integrity check. This bootstrap composes that sequence so
// the App target wires a single call and the sequence itself is testable in
// the package (constitution XII — tests are mandatory).
//
// Widgets do NOT use this: they open the database read-only, detect an
// unsupported schema via `StickyMigrator.currentSchemaVersion`, and fall
// back to privacy-safe placeholders without running any migration
// (research.md R6; plan §Local storage).

/// Composes interrupted-migration recovery, store opening, and schema
/// migration for app startup.
public enum DatabaseBootstrap {
    /// App Group container subpath for the database file.
    public static let databaseFileName = "stickynotes.sqlite"

    /// Backup file used during high-risk migrations. Lives beside the
    /// database file in the App Group container.
    public static func backupPath(forDatabasePath databasePath: String) -> String {
        databasePath + ".backup"
    }

    /// Recovers from any interrupted migration, opens the store (WAL,
    /// foreign keys, bounded busy timeout), and runs all pending migrations.
    ///
    /// - Parameters:
    ///   - databasePath: Absolute path to the SQLite file in the App Group
    ///     container.
    ///   - backupPath: Absolute path for the pre-migration backup.
    ///   - busyTimeout: SQLITE_BUSY timeout for the pool.
    /// - Returns: A ready store with the latest schema applied.
    /// - Throws: `.persistence(.recoveryFailed)` or `.migrationFailed` when
    ///   recovery/migration fails (never leaves a half-migrated DB behind —
    ///   the backup is restored on failure).
    public static func open(
        databasePath: String,
        backupPath: String,
        busyTimeout: TimeInterval = 5.0
    ) async throws -> DatabaseStore {
        // 1. Interrupted-migration recovery (T022, T153): if a previous
        //    launch crashed mid-migration, the backup holds the last known
        //    good state. Restore it before we try again.
        try MigrationRecovery.recoverFromInterruptedMigration(
            databasePath: databasePath,
            backupPath: backupPath
        )

        // 2. Open the pool (WAL, foreign keys, bounded busy timeout).
        let store = try DatabaseStore(path: databasePath, busyTimeout: busyTimeout)

        // 3. Pre-migration backup + migrate + post-migration integrity
        //    check, with restore-on-failure.
        let migrator = StickyMigrator(
            migrator: InitialSchema.migrator(),
            databasePath: databasePath,
            backupPath: backupPath
        )
        try await migrator.migrate(store.dbPool)
        return store
    }
}
