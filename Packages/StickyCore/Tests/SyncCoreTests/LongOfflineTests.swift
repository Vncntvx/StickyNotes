import Testing
import Foundation
import Domain
import Persistence
import SyncCore

// MARK: - Long-offline reconciliation tests (T163n / T124, US10)
//
// Per tasks.md T163n: "long-offline device reconciles deletion history
// before uploading locally-deleted notes; not wall-clock last-modified-wins".

@Suite struct LongOfflineTests {

    private func makeStore() throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    private func remoteTombstone(noteId: UUID, deletedVersionId: UUID) -> RemoteTombstone {
        RemoteTombstone(
            noteId: noteId,
            deletedVersionId: deletedVersionId,
            parentVersionId: nil,
            deletingDeviceId: UUID(),
            deletedAt: Date()
        )
    }

    @Test
    func remoteDeletionIsReconciledBeforeUpload() async throws {
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        let device = UUID()

        // A note deleted remotely (the local version descends from the
        // tombstone's deleted version).
        let note = Note(title: "old", lastModifiedDeviceId: device)
        try await repo.create(note)
        // Simulate the local version chain: version v1 → v2 (parent = v1).
        var edited = note
        edited.versionId = UUID()
        edited.parentVersionId = note.versionId
        try await repo.update(edited, modifyingDeviceId: device)

        let (toDelete, result) = try await OfflineReconciler.classify(
            store: store,
            remoteTombstones: [remoteTombstone(noteId: note.id, deletedVersionId: edited.versionId)]
        )
        #expect(toDelete.contains(note.id), "the remote deletion must be honored")
        #expect(result.withheldLocalDeletions == 0)
    }

    @Test
    func noRemoteDeletionRecordPreservesLocalNote() async throws {
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        let note = Note(title: "local only", lastModifiedDeviceId: UUID())
        try await repo.create(note)

        let (toDelete, result) = try await OfflineReconciler.classify(
            store: store,
            remoteTombstones: []   // history aged out
        )
        #expect(toDelete.isEmpty, "no remote deletion record → MUST NOT auto-delete local content (FR-174-b)")
        #expect(result.historyAgedOutDetected, "the user must be informed some sync history aged out (FR-174-d)")
        #expect(result.preservedNoteCount == 1)
    }

    @Test
    func locallyDeletedNoteIsNotReuploaded() async throws {
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        let note = Note(title: "deleted here", lastModifiedDeviceId: UUID())
        try await repo.create(note)
        try await repo.permanentlyDelete(id: note.id, deviceId: UUID())

        let (toDelete, result) = try await OfflineReconciler.classify(
            store: store,
            remoteTombstones: []   // remote history purged
        )
        #expect(toDelete.isEmpty)
        #expect(result.withheldLocalDeletions == 1,
                "notes deleted on the returning device must NOT be re-uploaded (FR-174-c)")
    }

    @Test
    func divergedLocalEditBecomesConflictCopyNotResurrection() async throws {
        // The local version diverged from the last known common ancestor →
        // a conflict copy is created on the next sync; the deleted note is
        // not resurrected as the original.
        let commonAncestor = UUID()
        let tombstoneVersion = UUID()
        // Local version is NOT a descendant of the tombstone version.
        let localVersion = UUID()

        let decision = OfflineReconciler.decide(
            localVersionId: localVersion,
            localParentVersionId: commonAncestor,
            localLifecycle: .active,
            remoteTombstoneVersionId: tombstoneVersion
        )
        // Not honored as deletion (local content diverged from deleted
        // lineage) → preserved; the engine creates a conflict copy on the
        // next sync (FR-174-e).
        #expect(decision == .preserveNoRemoteDeletionRecord)
    }

    @Test
    func notWallClockLastModifiedWins() {
        // A very RECENT local version descending from an OLD deleted version
        // is still deleted (lineage wins, not timestamps).
        let oldDeletedVersion = UUID()
        let recentLocal = UUID()
        let decision = OfflineReconciler.decide(
            localVersionId: recentLocal,
            localParentVersionId: oldDeletedVersion,
            localLifecycle: .active,
            remoteTombstoneVersionId: oldDeletedVersion
        )
        #expect(decision == .honorRemoteDeletion,
                "lineage-based reconciliation — NOT wall-clock last-modified-wins")
    }
}
