import Foundation
import GRDB
import Domain

// MARK: - FileLocatorRepository (T291, FR-105)
//
// Per tasks.md T291 and data-model.md §FileLocator: device-local persistence
// of the security-scoped bookmark + availability state for a file-reference
// block. Bookmark bytes and absolute paths are NEVER synchronized (FR-105;
// constitution IX). The `fileLocator` table exists in the v1 schema; this
// repository is the App's access path.

/// Repository for device-local file locators (bookmark bytes + availability).
public final class SQLiteFileLocatorRepository: Sendable {
    private let store: DatabaseStore

    public init(store: DatabaseStore) {
        self.store = store
    }

    /// Fetches the locator for a block, or nil when the file was never
    /// linked on this device (FR-104 on-another-device state).
    public func fetch(blockId: UUID) async throws -> FileLocator? {
        try await store.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM fileLocator WHERE blockId = ?",
                arguments: [blockId.uuidString]
            ) else { return nil }
            return FileLocator(
                blockId: UUID(uuidString: row["blockId"] ?? "") ?? blockId,
                bookmarkData: row["bookmarkData"],
                lastResolvedPath: row["lastResolvedPath"] ?? "",
                availabilityStatus: FileAvailability(rawValue: row["availabilityStatus"] ?? "available") ?? .available,
                stale: row["stale"] ?? false,
                verifiedAt: row["verifiedAt"]
            )
        }
    }

    /// Inserts or replaces the locator (relink / verify updates).
    public func upsert(_ locator: FileLocator) async throws {
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO fileLocator (blockId, bookmarkData, lastResolvedPath, availabilityStatus, stale, verifiedAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(blockId) DO UPDATE SET
                        bookmarkData = excluded.bookmarkData,
                        lastResolvedPath = excluded.lastResolvedPath,
                        availabilityStatus = excluded.availabilityStatus,
                        stale = excluded.stale,
                        verifiedAt = excluded.verifiedAt
                    """,
                arguments: [
                    locator.blockId.uuidString,
                    locator.bookmarkData,
                    locator.lastResolvedPath,
                    locator.availabilityStatus.rawValue,
                    locator.stale,
                    locator.verifiedAt,
                ]
            )
        }
    }

    /// Removes the locator (block removed / user cleared the link).
    public func delete(blockId: UUID) async throws {
        try await store.write { db in
            try db.execute(
                sql: "DELETE FROM fileLocator WHERE blockId = ?",
                arguments: [blockId.uuidString]
            )
        }
    }
}
