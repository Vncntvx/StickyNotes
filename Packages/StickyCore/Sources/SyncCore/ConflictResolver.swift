import Foundation
import GRDB
import Domain
import Persistence

// MARK: - Content divergence classifier (T232, FR-022b)
//
// Per tasks.md T232 and spec FR-022b (clarified 2026-08-07): divergence
// detection evaluates CONTENT fields only. When the ONLY differing field is
// `manualSortKey`, the engine applies the most recently written sort key
// (per-note LWW by version timestamp/sequence) WITHOUT recording divergence
// and WITHOUT creating a conflict copy. Crossed reorders resolve per-note by
// version recency — no global order arbitration.

/// Classifies the divergence between a local and a remote note version.
public enum ContentDivergence {

    /// The content fields of a note (excluding manualSortKey — FR-022b).
    public static func contentFieldsAreEqual(_ local: CanonicalNote, _ remote: CanonicalNote) -> Bool {
        guard local.id == remote.id else { return false }
        guard local.title == remote.title else { return false }
        guard local.colorKey == remote.colorKey else { return false }
        guard local.customColor == remote.customColor else { return false }
        guard local.transparency == remote.transparency else { return false }
        guard local.textSize == remote.textSize else { return false }
        guard local.alwaysOnTop == remote.alwaysOnTop else { return false }
        guard local.widgetEligible == remote.widgetEligible else { return false }
        guard local.coverScreenshotBlockId == remote.coverScreenshotBlockId else { return false }
        guard local.lifecycleState == remote.lifecycleState else { return false }
        guard local.trashedAt == remote.trashedAt else { return false }
        guard local.conflictOriginNoteId == remote.conflictOriginNoteId else { return false }
        guard local.conflictLabel == remote.conflictLabel else { return false }
        guard local.blocks == remote.blocks else { return false }
        return true
    }

    /// Whether the two versions differ ONLY in `manualSortKey` (and the
    /// version-lineage fields, which always differ between versions).
    public static func differsOnlyBySortKey(_ local: CanonicalNote, _ remote: CanonicalNote) -> Bool {
        guard local.id == remote.id else { return false }
        guard contentFieldsAreEqual(local, remote) else { return false }
        return local.manualSortKey != remote.manualSortKey
    }

    /// The sort-key LWW decision per FR-022b: the version with the NEWER
    /// `modifiedAt` wins the sort key; a tie breaks by versionId string
    /// comparison (deterministic). Returns the winning sort key.
    public static func lastWriterWinsSortKey(local: CanonicalNote, remote: CanonicalNote) -> Int {
        if local.modifiedAt > remote.modifiedAt {
            return local.manualSortKey
        }
        if remote.modifiedAt > local.modifiedAt {
            return remote.manualSortKey
        }
        // Tie: deterministic by version UUID string (stable across devices).
        return local.versionId.uuidString > remote.versionId.uuidString
            ? local.manualSortKey
            : remote.manualSortKey
    }
}

// MARK: - SyncConflictResolver (T171)

/// The default conflict resolver: sorts out the divergence via conflict
/// copies with deterministic dedup (US10). Conforms to the engine's
/// `ConflictResolver` hook.
public struct SyncConflictResolver: ConflictResolver, Sendable {
    private let store: DatabaseStore

    public init(store: DatabaseStore) {
        self.store = store
    }

    public func resolveDivergence(
        local: CanonicalNote,
        remote: CanonicalNote,
        deviceId: UUID
    ) async throws -> ConflictResolutionOutcome {
        // FR-022b: sort-key-only divergence NEVER creates a conflict copy.
        if ContentDivergence.differsOnlyBySortKey(local, remote) {
            // Apply the LWW sort key onto the local note (deterministic per
            // version recency). Content is untouched.
            let winningKey = ContentDivergence.lastWriterWinsSortKey(local: local, remote: remote)
            try await store.write { db in
                try db.execute(
                    sql: """
                        UPDATE note SET
                            manualSortKey = ?,
                            versionId = ?,
                            parentVersionId = (SELECT versionId FROM note WHERE id = ?),
                            lastModifiedDeviceId = ?,
                            modifiedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        winningKey,
                        UUID().uuidString,
                        local.id.uuidString,
                        deviceId.uuidString,
                        Date(),
                        local.id.uuidString,
                    ]
                )
            }
            return .notAContentConflict
        }

        // Content divergence: keep the local version as the original and
        // preserve the remote as a labeled conflict copy. Which side is
        // "original" vs "copy" is deterministic by version recency: the
        // NEWER local version stays; the other becomes the copy. (When the
        // remote is newer, the local version becomes the conflict copy so
        // the user's newest edits are not obscured.)
        let outcome = try await store.write { db in
            try ConflictCopyBuilder.createConflictCopy(
                in: db,
                originalNoteId: local.id,
                localVersionId: local.versionId,
                remote: remote,
                deviceId: deviceId
            )
        }
        // T302: the outcome distinguishes NEW copies (created) from dedup
        // hits (alreadyExists) so the engine counts precisely.
        switch outcome {
        case .created:
            return .created
        case .alreadyExists:
            return .alreadyExists
        case .notAContentConflict:
            return .notAContentConflict
        }
    }
}
