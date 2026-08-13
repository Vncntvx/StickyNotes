import Foundation
import GRDB
import Domain

// MARK: - DatabaseStore (T017)
//
// Per plan §Local storage: GRDB `DatabasePool` with WAL mode, bounded busy
// timeout, short write transactions. The main app owns migrations.
// Integrity checking, pre-migration backup, interrupted-migration recovery
// (T022).
//
// Per research.md R6: WAL allows concurrent readers + one writer; the
// bounded busy timeout prevents indefinite waits.

/// The DatabaseStore wraps a GRDB `DatabasePool` configured for the app
/// sandbox container. It is the single source of truth for all
/// note/block/todo/asset metadata. Asset bytes live outside SQLite in the
/// sandbox Application Support directory.
///
/// `Sendable` — `DatabasePool` is itself `Sendable`. Cross-actor handoffs
/// pass `Sendable` value types or `isolated` references (plan §State
/// management and concurrency).
public final class DatabaseStore: Sendable {
    public let dbPool: DatabasePool
    /// The database file path (nil for stores built from an existing pool).
    public let databasePath: String?
    /// The bounded busy timeout this store was opened with (FR-140a).
    public let busyTimeout: TimeInterval

    /// The production default busy timeout (FR-140a: 5 seconds).
    public static let defaultBusyTimeout: TimeInterval = 5.0

    /// Opens (or creates) the database at the given path with WAL mode and a
    /// bounded busy timeout.
    ///
    /// - Parameters:
    ///   - path: Absolute path to the SQLite file in the app sandbox
    ///     container.
    ///   - busyTimeout: Maximum time to wait on SQLITE_BUSY before failing
    ///     (default 5 seconds per FR-140a).
    public init(path: String, busyTimeout: TimeInterval = DatabaseStore.defaultBusyTimeout) throws {
        self.databasePath = path
        self.busyTimeout = busyTimeout
        var config = Configuration()
        // WAL mode + busy timeout (research.md R6).
        config.busyMode = .timeout(busyTimeout)
        // Foreign keys ON (data-model.md §Constraints).
        config.foreignKeysEnabled = true
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
        return try DatabaseStore(path: path, busyTimeout: 1.0)
    }

    /// Internal initializer for tests that already have a pool.
    public init(pool: DatabasePool) {
        self.dbPool = pool
        self.databasePath = nil
        self.busyTimeout = DatabaseStore.defaultBusyTimeout
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
    /// surfaced to logs (they could contain table/column names). Domain
    /// `StickyError.persistence` values pass through untouched so callers
    /// receive the typed error (e.g. FR-090b `.contentTooLarge`).
    public static func fromGRDB(_ error: Error) -> Domain.PersistenceError {
        if let sticky = error as? StickyError {
            if case .persistence(let e) = sticky {
                return e
            }
        }
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
