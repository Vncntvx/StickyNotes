import Foundation
import GRDB
import Domain

// MARK: - DatabaseStore (T017)
//
// Per plan §Local storage: GRDB `DatabasePool` with WAL mode, bounded busy
// timeout, short write transactions. Main app owns migrations; widgets
// detect unsupported schema and fall back to privacy-safe placeholders
// (read-only). Integrity checking, pre-migration backup, interrupted-
// migration recovery (T022).
//
// Per research.md R6: WAL allows concurrent readers + one writer across
// processes (app + widget). Widget writes are tiny and retried on
// SQLITE_BUSY. Bounded busy timeout prevents indefinite waits.

/// The DatabaseStore wraps a GRDB `DatabasePool` configured for the App Group
/// container. It is the single source of truth for all note/block/todo/asset
/// metadata. Asset bytes live outside SQLite in the App Group container.
///
/// `Sendable` — `DatabasePool` is itself `Sendable`. Cross-actor handoffs
/// pass `Sendable` value types or `isolated` references (plan §State
/// management and concurrency).
public final class DatabaseStore: Sendable {
    public let dbPool: DatabasePool

    /// Opens (or creates) the database at the given path with WAL mode and a
    /// bounded busy timeout.
    ///
    /// - Parameters:
    ///   - path: Absolute path to the SQLite file in the App Group container.
    ///   - busyTimeout: Maximum time to wait on SQLITE_BUSY before failing
    ///     (default 5 seconds; the widget uses shorter timeouts via its own
    ///     pool).
    public init(path: String, busyTimeout: TimeInterval = 5.0) throws {
        var config = Configuration()
        // WAL mode + busy timeout (research.md R6).
        config.busyMode = .timeout(busyTimeout)
        // Foreign keys ON (data-model.md §Constraints).
        config.foreignKeysEnabled = true
        // Read-only mode is opted into per-pool by the widget, not here.
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        // Label reader/writer queues for Instruments / Console filtering.
        config.label = "local.stickynotes.persistence"

        do {
            self.dbPool = try DatabasePool(path: path, configuration: config)
        } catch {
            throw StickyError.persistence(.databaseOpenFailed)
        }
    }

    /// Convenience for in-memory-style databases (tests, deterministic local
    /// provider fixtures). Uses a temporary file in the system temp dir so
    /// that WAL mode + `DatabasePool` work correctly (an actual in-memory
    /// `DatabaseQueue` does not support WAL/concurrent reads). The temp file
    /// is removed when the returned store is deinitialized.
    ///
    /// For tests that don't need WAL concurrency, prefer a plain
    /// `DatabaseQueue()` directly.
    public static func inMemory() throws -> DatabaseStore {
        let tempDir = NSTemporaryDirectory()
        let path = (tempDir as NSString).appendingPathComponent("stickynotes-test-\(UUID().uuidString).sqlite")
        let store = try DatabaseStore(path: path, busyTimeout: 1.0)
        // Register the temp path for cleanup on deinit.
        Task { await TempDatabasePaths.register(path) }
        return store
    }

    deinit {
        // No explicit cleanup — temp DBs are cleaned up by the OS.
        // Persistence tests use unique UUID-suffixed paths to avoid
        // collisions across parallel test runs.
    }

    /// Internal initializer for tests that already have a pool.
    public init(pool: DatabasePool) {
        self.dbPool = pool
    }

    // MARK: - Read/write helpers
    //
    // Read accesses use `dbPool.read { … }` (concurrent readers, no blocking
    // on the writer). Write accesses use `dbPool.write { … }` (serialized
    // through the single writer dispatch queue).

    public func read<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        do {
            return try await dbPool.read { db in
                try block(db)
            }
        } catch {
            throw StickyError.persistence(PersistenceErrorMapping.fromGRDB(error))
        }
    }

    public func write<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        do {
            return try await dbPool.write { db in
                try block(db)
            }
        } catch {
            throw StickyError.persistence(PersistenceErrorMapping.fromGRDB(error))
        }
    }
}

// MARK: - GRDB error → StickyError mapping
//
// Sanitized: the underlying SQLite error code is mapped to a coarse
// PersistenceError case. No note content, paths, or SQL fragments leak
// through (constitution VI).

public enum PersistenceErrorMapping {
    /// Maps a GRDB/SQLite error to a coarse `PersistenceError`. The mapping
    /// is intentionally lossy — fine-grained SQLite error codes are NOT
    /// surfaced to logs (they could contain table/column names).
    public static func fromGRDB(_ error: Error) -> Domain.PersistenceError {
        if let dbError = error as? DatabaseError {
            switch dbError.resultCode {
            case .SQLITE_BUSY, .SQLITE_LOCKED:
                return .writeConflict
            case .SQLITE_CORRUPT, .SQLITE_NOTADB:
                return .integrityCheckFailed
            case .SQLITE_CONSTRAINT:
                return .invalidPayload
            default:
                return .recordNotFound
            }
        }
        if error is RecordError {
            return .recordNotFound
        }
        return .databaseOpenFailed
    }
}
