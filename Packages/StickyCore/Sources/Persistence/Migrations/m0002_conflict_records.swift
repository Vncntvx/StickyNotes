import Foundation
import GRDB
import Domain

// MARK: - Migration v2: conflict records (T171, US10)
//
// Per plan §Conflict model: conflict-copy deduplication uses a
// reconciliation record keyed by (originalNoteId, localVersionId,
// remoteVersionId) so a retried sync never creates unbounded duplicate
// conflict copies. This table is device-local sync bookkeeping (never
// synchronized; not note content).

public enum StickyMigrationIdV2 {
    public static let v2 = "v2_conflict_records"
}

/// Extends the v1 migrator with the v2 conflict-record table.
public enum ConflictRecordSchema {
    public static func migrateV2(_ db: Database) throws {
        try db.create(table: "conflictRecord") { t in
            t.column("originalNoteId", .text).notNull()
            t.column("localVersionId", .text).notNull()
            t.column("remoteVersionId", .text).notNull()
            // The conflict copy that was created for this divergence.
            t.column("conflictNoteId", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            // Deterministic dedup key (plan §Conflict model).
            t.primaryKey(["originalNoteId", "localVersionId", "remoteVersionId"])
        }
        try db.create(index: "conflictRecord_originalNoteId", on: "conflictRecord", columns: ["originalNoteId"])
    }
}
