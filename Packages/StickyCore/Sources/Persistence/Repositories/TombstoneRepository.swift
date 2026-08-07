import Foundation
import GRDB
import Domain

// MARK: - TombstoneRepository (T171/T128)
//
// Per tasks.md T171 and plan §Deletion and tombstones: a tombstone store with
// 30-day sync-safety-gated retention (contracts/tombstone.schema.json +
// data-model.md §Tombstone lifecycle).
//
// - A tombstone is never purged while any known device could still be
//   offline within the retention window (sync-safety check).
// - `canPurgeRemote` flips only when all known devices have confirmed seeing
//   the deletion (the sync engine drives this).
// - The expiry scan (T078 TrashExpiryTests) transitions trashed notes to
//   permanentlyDeleted; this repository manages the tombstone records
//   themselves.

/// Tombstone repository: CRUD + retention policy for deletion records.
public protocol TombstoneRepositoryProtocol: Sendable {
    /// Records a tombstone for a note (upsert on noteId).
    func record(_ tombstone: Tombstone) async throws

    /// Fetches a tombstone by note id.
    func fetch(noteId: UUID) async throws -> Tombstone?

    /// Fetches all tombstones.
    func fetchAll() async throws -> [Tombstone]

    /// Marks a tombstone's remote copy as safely purgable (sync-safety gate
    /// passed: all known devices have confirmed the deletion).
    func markRemotePurgable(noteId: UUID) async throws

    /// Purges tombstones whose deletion is older than `retentionDays` AND
    /// whose `canPurgeRemote` is true (sync-safety gated). Returns the
    /// purged note ids.
    @discardableResult
    func purgeExpired(now: Date, retentionDays: Int) async throws -> [UUID]

    /// Deletes a tombstone record (manual Trash empty path).
    func delete(noteId: UUID) async throws
}

/// SQLite-backed tombstone repository.
public final class SQLiteTombstoneRepository: TombstoneRepositoryProtocol, Sendable {
    /// The retention window (data-model.md §Tombstone lifecycle): 30 days.
    public static let defaultRetentionDays = 30

    private let store: DatabaseStore

    public init(store: DatabaseStore) {
        self.store = store
    }

    public func record(_ tombstone: Tombstone) async throws {
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tombstone (
                        noteId, deletedVersionId, parentVersionId, deletingDeviceId,
                        deletedAt, purgedAt, canPurgeRemote
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(noteId) DO UPDATE SET
                        deletedVersionId = excluded.deletedVersionId,
                        parentVersionId = excluded.parentVersionId,
                        deletingDeviceId = excluded.deletingDeviceId,
                        deletedAt = excluded.deletedAt,
                        purgedAt = excluded.purgedAt,
                        canPurgeRemote = excluded.canPurgeRemote
                    """,
                arguments: [
                    tombstone.noteId.uuidString,
                    tombstone.deletedVersionId.uuidString,
                    tombstone.parentVersionId?.uuidString,
                    tombstone.deletingDeviceId.uuidString,
                    tombstone.deletedAt,
                    tombstone.purgedAt,
                    tombstone.canPurgeRemote,
                ]
            )
        }
    }

    public func fetch(noteId: UUID) async throws -> Tombstone? {
        try await store.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM tombstone WHERE noteId = ?",
                arguments: [noteId.uuidString]
            ) else { return nil }
            return try Self.tombstone(from: row)
        }
    }

    public func fetchAll() async throws -> [Tombstone] {
        try await store.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM tombstone ORDER BY deletedAt")
            return rows.compactMap { try? Self.tombstone(from: $0) }
        }
    }

    public func markRemotePurgable(noteId: UUID) async throws {
        try await store.write { db in
            try db.execute(
                sql: "UPDATE tombstone SET canPurgeRemote = 1 WHERE noteId = ?",
                arguments: [noteId.uuidString]
            )
        }
    }

    @discardableResult
    public func purgeExpired(now: Date, retentionDays: Int = SQLiteTombstoneRepository.defaultRetentionDays) async throws -> [UUID] {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return try await store.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM tombstone
                    WHERE deletedAt < ? AND canPurgeRemote = 1
                    """,
                arguments: [cutoff]
            )
            let ids = rows.compactMap { row -> UUID? in
                UUID(uuidString: row["noteId"] ?? "")
            }
            for id in ids {
                try db.execute(
                    sql: "DELETE FROM tombstone WHERE noteId = ?",
                    arguments: [id.uuidString]
                )
            }
            return ids
        }
    }

    public func delete(noteId: UUID) async throws {
        try await store.write { db in
            try db.execute(
                sql: "DELETE FROM tombstone WHERE noteId = ?",
                arguments: [noteId.uuidString]
            )
        }
    }

    private static func tombstone(from row: Row) throws -> Tombstone {
        Tombstone(
            noteId: UUID(uuidString: row["noteId"] ?? "") ?? UUID(),
            deletedVersionId: UUID(uuidString: row["deletedVersionId"] ?? "") ?? UUID(),
            parentVersionId: (row["parentVersionId"] as String?).flatMap { UUID(uuidString: $0) },
            deletingDeviceId: UUID(uuidString: row["deletingDeviceId"] ?? "") ?? UUID(),
            deletedAt: row["deletedAt"] ?? Date(),
            purgedAt: row["purgedAt"],
            canPurgeRemote: row["canPurgeRemote"] ?? false
        )
    }
}
