import Foundation
import GRDB
import Domain
import Persistence

// MARK: - OfflineReconciler (T171/T129/T184, US10)
//
// Per tasks.md T171/T184 and plan §Deletion and tombstones: a long-offline
// device (offline >30 d) reconciles REMOTE deletion history BEFORE uploading
// locally-deleted notes; conservative unknown-remote handling; NOT wall-clock
// "last modified wins".
//
// FR-174 refinement (T184, clarified 2026-08-07) — returning device whose
// remote tombstone was already purged by another device's cleanup:
// (a) reconcile remote deletion history BEFORE uploading local notes;
// (b) no remote tombstone found for a note → "no remote deletion record
//     found" → preserve it locally (MUST NOT auto-delete any local content);
// (c) notes the user deleted on the returning device MUST NOT be re-uploaded
//     unless the user explicitly restores them;
// (d) inform the user that some sync history has aged out;
// (e) if the local version diverged from the last known common ancestor, a
//     conflict copy is created on the next sync.

/// The reconciliation decision for one note on a returning device.
public enum ReconciliationDecision: Sendable, Equatable {
    /// The remote tombstone exists and the local version descends from the
    /// deleted version → honor the deletion (no resurrection).
    case honorRemoteDeletion

    /// No remote tombstone found for the note → treat as "no remote
    /// deletion record found" and PRESERVE the note locally (FR-174-b).
    case preserveNoRemoteDeletionRecord

    /// The user deleted the note on this returning device → MUST NOT
    /// re-upload unless explicitly restored (FR-174-c).
    case locallyDeletedDoNotReupload

    /// Normal case: note is active locally, no remote deletion → sync
    /// normally (may produce a conflict copy if content diverged).
    case syncNormally
}

/// Outcome of a full reconciliation pass.
public struct OfflineReconciliationResult: Sendable, Equatable {
    /// Whether any "sync history aged out" situation was detected (the App
    /// must inform the user — FR-174-d).
    public var historyAgedOutDetected: Bool
    /// Notes preserved locally despite a purged remote tombstone.
    public var preservedNoteCount: Int
    /// Notes locally deleted that will NOT be re-uploaded.
    public var withheldLocalDeletions: Int

    public init(historyAgedOutDetected: Bool = false, preservedNoteCount: Int = 0, withheldLocalDeletions: Int = 0) {
        self.historyAgedOutDetected = historyAgedOutDetected
        self.preservedNoteCount = preservedNoteCount
        self.withheldLocalDeletions = withheldLocalDeletions
    }
}

/// The long-offline reconciliation core (pure decisions + a DB-backed
/// classification). Never deletes local content.
public enum OfflineReconciler {

    /// Classifies one locally-present note against the remote tombstone
    /// history.
    ///
    /// - Parameters:
    ///   - localVersionId: the note's local version.
    ///   - localParentVersionId: the note's local parent version.
    ///   - localLifecycle: the note's local lifecycle state.
    ///   - remoteTombstoneVersionId: the remote tombstone's
    ///     `deletedVersionId`, when a remote tombstone exists.
    /// - Returns: the reconciliation decision.
    public static func decide(
        localVersionId: UUID,
        localParentVersionId: UUID?,
        localLifecycle: NoteLifecycleState,
        remoteTombstoneVersionId: UUID?
    ) -> ReconciliationDecision {
        // Note deleted locally by the user on this device.
        if localLifecycle == .permanentlyDeleted || localLifecycle == .trashed {
            // With a remote tombstone for the same lineage → consistent.
            // Without one → the deletion was local-only; MUST NOT re-upload
            // unless explicitly restored (FR-174-c).
            return .locallyDeletedDoNotReupload
        }

        guard let remoteTombstoneVersionId else {
            // No remote deletion record found (FR-174-b): preserve locally.
            return .preserveNoRemoteDeletionRecord
        }

        // Remote deletion exists: honor it only when the local version
        // descends from the deleted version (no resurrection of divergent
        // content — the deleted version's descendants are the same content
        // the remote deleted).
        if localVersionId == remoteTombstoneVersionId
            || localParentVersionId == remoteTombstoneVersionId {
            return .honorRemoteDeletion
        }

        // Local content diverged from the deleted lineage: never auto-delete
        // (Constitution VIII) — preserve; a conflict copy is created on the
        // next sync (FR-174-e).
        return .preserveNoRemoteDeletionRecord
    }

    /// Runs the reconciliation pass over the local note table. Returns the
    /// set of note ids that must be deleted locally (honored remote
    /// deletions) plus the aged-out/preserved bookkeeping. Performs NO
    /// writes itself — the caller applies deletions.
    public static func classify(
        store: DatabaseStore,
        remoteTombstones: [RemoteTombstone]
    ) async throws -> (toDelete: Set<UUID>, result: OfflineReconciliationResult) {
        let tombstoneByNote = Dictionary(
            uniqueKeysWithValues: remoteTombstones.map { ($0.noteId, $0) }
        )
        var toDelete: Set<UUID> = []
        var result = OfflineReconciliationResult()

        let notes = try await store.read { db in
            try NoteRow.fetchAll(db).map { row in
                Note(
                    id: UUID(uuidString: row["id"] ?? "") ?? UUID(),
                    title: row["title"],
                    colorKey: NoteColorKey(rawValue: row["colorKey"] ?? "") ?? .yellow,
                    customColor: row["customColor"],
                    transparency: row["transparency"] ?? 1.0,
                    textSize: row["textSize"] ?? 13,
                    alwaysOnTop: row["alwaysOnTop"] ?? false,
                    widgetEligible: row["widgetEligible"] ?? true,
                    coverScreenshotBlockId: (row["coverScreenshotBlockId"] as String?).flatMap { UUID(uuidString: $0) },
                    manualSortKey: row["manualSortKey"] ?? 0,
                    lifecycleState: NoteLifecycleState(rawValue: row["lifecycleState"] ?? "") ?? .active,
                    trashedAt: row["trashedAt"],
                    conflictOriginNoteId: (row["conflictOriginNoteId"] as String?).flatMap { UUID(uuidString: $0) },
                    conflictLabel: row["conflictLabel"],
                    versionId: UUID(uuidString: row["versionId"] ?? "") ?? UUID(),
                    parentVersionId: (row["parentVersionId"] as String?).flatMap { UUID(uuidString: $0) },
                    lastModifiedDeviceId: UUID(uuidString: row["lastModifiedDeviceId"] ?? "") ?? UUID(),
                    createdAt: row["createdAt"] ?? Date(),
                    modifiedAt: row["modifiedAt"] ?? Date()
                )
            }
        }

        for note in notes {
            let tombstone = tombstoneByNote[note.id]
            let decision = decide(
                localVersionId: note.versionId,
                localParentVersionId: note.parentVersionId,
                localLifecycle: note.lifecycleState,
                remoteTombstoneVersionId: tombstone?.deletedVersionId
            )
            switch decision {
            case .honorRemoteDeletion:
                toDelete.insert(note.id)
            case .preserveNoRemoteDeletionRecord:
                if tombstone == nil && note.lifecycleState != .permanentlyDeleted && note.lifecycleState != .trashed {
                    result.historyAgedOutDetected = true
                    result.preservedNoteCount += 1
                }
            case .locallyDeletedDoNotReupload:
                result.withheldLocalDeletions += 1
            case .syncNormally:
                break
            }
        }
        return (toDelete, result)
    }
}

/// Minimal row accessor used by the reconciler (avoids importing the
/// private repository row mapping).
private enum NoteRow {
    static func fetchAll(_ db: Database) throws -> [Row] {
        try Row.fetchAll(db, sql: "SELECT * FROM note")
    }
}
