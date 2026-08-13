import Foundation
import GRDB
import Domain

// MARK: - DatabaseBootstrap (T154)
//
// Opens the app's SQLite database. There is no migration chain and no
// backward compatibility (pre-release app): a single schema migration
// (`InitialSchema`) creates the full current schema on a fresh database and
// is a no-op on an existing one. This bootstrap composes open + migrate so
// the App target wires a single call and the sequence is testable in the
// package (constitution XII — tests are mandatory).

/// Composes store opening and the single schema migration for app startup.
public enum DatabaseBootstrap {
    /// Sandbox Application Support subpath for the database file.
    public static let databaseFileName = "stickynotes.sqlite"

    /// Opens the store (WAL, foreign keys, bounded busy timeout) and applies
    /// the single current schema.
    ///
    /// - Parameters:
    ///   - databasePath: Absolute path to the SQLite file in the sandbox
    ///     container.
    ///   - busyTimeout: SQLITE_BUSY timeout for the pool.
    /// - Returns: A ready store with the current schema applied.
    public static func open(
        databasePath: String,
        busyTimeout: TimeInterval = 5.0
    ) async throws -> DatabaseStore {
        let store = try DatabaseStore(path: databasePath, busyTimeout: busyTimeout)
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }
}
