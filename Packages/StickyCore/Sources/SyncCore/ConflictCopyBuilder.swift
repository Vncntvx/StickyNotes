import Foundation
import GRDB
import Domain
import Persistence

// MARK: - ConflictCopyBuilder (T171/T127, US10)
//
// Per tasks.md T171 and plan §Conflict model: on divergence the divergent
// version becomes a conflict copy — a NEW note UUID, labeled with origin +
// time, preserving text/todos/code/images/screenshots/file-reference
// metadata, with assets kept by safe duplication/reference. NO character/
// block auto-merge. The conflict copy syncs normally (it is just another
// note).
//
// Deterministic dedup: a `conflictRecord` row keyed by
// (originalNoteId, localVersionId, remoteVersionId) records the conflict
// copy, so a retried sync never creates unbounded duplicates (Constitution
// VIII).

/// Outcome of a conflict-copy attempt.
public enum ConflictCopyOutcome: Sendable, Equatable {
    /// A new conflict copy was created.
    case created(conflictNoteId: UUID)
    /// A conflict copy already exists for this divergence (dedup hit).
    case alreadyExists(conflictNoteId: UUID)
    /// The divergence is NOT a content conflict (e.g. sort-key-only —
    /// handled by the LWW path, FR-022b).
    case notAContentConflict
}

/// Builds conflict copies for divergent note versions (US10).
public enum ConflictCopyBuilder {

    /// The conflict-copy label format (language-neutral; the App layer
    /// localizes): "origin device-time" style label per data-model.md
    /// §Conflict-copy lifecycle.
    public static func label(originDeviceId: UUID, modifiedAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "conflict-copy-\(formatter.string(from: modifiedAt))-\(originDeviceId.uuidString.prefix(8))"
    }

    /// Creates a conflict copy of the divergent `remote` version (the one
    /// that lost the race) inside a write transaction.
    ///
    /// - Parameters:
    ///   - db: the write transaction.
    ///   - originalNoteId: the shared note identity.
    ///   - localVersionId: the local version at divergence.
    ///   - remote: the divergent remote version to preserve as the copy.
    ///   - deviceId: the local device.
    /// - Returns: the outcome (created / alreadyExists / notAContentConflict).
    /// - Throws: only on genuine persistence errors — the conflict copy
    ///   path never partially writes (single transaction).
    public static func createConflictCopy(
        in db: Database,
        originalNoteId: UUID,
        localVersionId: UUID,
        remote: CanonicalNote,
        deviceId: UUID
    ) throws -> ConflictCopyOutcome {
        // Deterministic dedup key (plan §Conflict model).
        let existing: String? = try String.fetchOne(
            db,
            sql: """
                SELECT conflictNoteId FROM conflictRecord
                WHERE originalNoteId = ? AND localVersionId = ? AND remoteVersionId = ?
                """,
            arguments: [originalNoteId.uuidString, localVersionId.uuidString, remote.versionId.uuidString]
        )
        if let existing, let conflictId = UUID(uuidString: existing) {
            return .alreadyExists(conflictNoteId: conflictId)
        }

        let now = Date()
        let conflictNoteId = UUID()
        let versionId = UUID()
        // The conflict copy inherits the divergent version's content but
        // gets its OWN lineage (parent = the remote version's parent, i.e.
        // the common ancestor where divergence started).
        let parentVersionId = remote.parentVersionId

        // 1. Note row (lifecycleState = conflictCopy; distinguishable).
        try db.execute(
            sql: """
                INSERT INTO note (
                    id, title, colorKey, customColor, transparency, textSize,
                    alwaysOnTop, coverScreenshotBlockId, manualSortKey,
                    lifecycleState, trashedAt, conflictOriginNoteId, conflictLabel,
                    versionId, parentVersionId, lastModifiedDeviceId, createdAt, modifiedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'conflictCopy', NULL, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                conflictNoteId.uuidString,
                remote.title,
                remote.colorKey.rawValue,
                remote.customColor,
                remote.transparency,
                remote.textSize,
                remote.alwaysOnTop,
                remote.coverScreenshotBlockId?.uuidString,
                ManualSortKeys.initialSortKey,
                originalNoteId.uuidString,
                label(originDeviceId: remote.lastModifiedDeviceId, modifiedAt: remote.modifiedAt),
                versionId.uuidString,
                parentVersionId?.uuidString,
                deviceId.uuidString,
                now,
                now,
            ]
        )

        // 2. Blocks (payload-preserving copies with new block ids — the
        //    payload is byte-identical so no content is lost).
        for block in remote.blocks {
            let payloadJSON = try CanonicalJSONEncoder().encodeString(block.payload)
            try db.execute(
                sql: """
                    INSERT INTO block (id, noteId, kind, sortKey, payload, versionId,
                                       parentVersionId, lastModifiedDeviceId, createdAt, modifiedAt)
                    VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?)
                    """,
                arguments: [
                    UUID().uuidString,
                    conflictNoteId.uuidString,
                    block.kind.rawValue,
                    block.sortKey,
                    payloadJSON,
                    UUID().uuidString,
                    deviceId.uuidString,
                    block.createdAt,
                    block.modifiedAt,
                ]
            )
        }

        // 3. Dedup record (single transaction — retry can't duplicate).
        try db.execute(
            sql: """
                INSERT INTO conflictRecord (originalNoteId, localVersionId, remoteVersionId,
                                            conflictNoteId, createdAt)
                VALUES (?, ?, ?, ?, ?)
                """,
            arguments: [
                originalNoteId.uuidString,
                localVersionId.uuidString,
                remote.versionId.uuidString,
                conflictNoteId.uuidString,
                now,
            ]
        )

        return .created(conflictNoteId: conflictNoteId)
    }
}
