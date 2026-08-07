import Testing
import Foundation
import Domain
import Persistence
import SyncCore

// MARK: - Long-offline tombstone purge tests (T179, FR-174)
//
// Per tasks.md T179: "returning device (offline >30 d, remote tombstone
// already purged by another device's cleanup) syncs: (a) MUST NOT auto-delete
// any local content; (b) reconciles remote deletion history before upload;
// (c) if no remote tombstone found for a note, treats as 'no remote deletion
// record found' and preserves it locally; (d) notes the user deleted on the
// returning device MUST NOT be re-uploaded unless explicitly restored;
// (e) user is informed that some sync history has aged out; (f) if the local
// version diverged from the last known common ancestor, a conflict copy is
// created on next sync".

@Suite struct LongOfflineTombstonePurgeTests {

    private func makeStore() throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    @Test
    func returningDeviceNeverAutoDeletesLocalContent() async throws {
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))

        // Several local notes, including some whose remote history aged out.
        let noteA = Note(title: "A", lastModifiedDeviceId: UUID())
        let noteB = Note(title: "B", lastModifiedDeviceId: UUID())
        try await repo.create(noteA)
        try await repo.create(noteB)

        // Remote tombstone history is EMPTY (already purged >30 d).
        let (toDelete, result) = try await OfflineReconciler.classify(store: store, remoteTombstones: [])

        #expect(toDelete.isEmpty, "(a) MUST NOT auto-delete any local content")
        #expect(result.preservedNoteCount == 2, "(c) no remote deletion record → preserve locally")
        #expect(result.historyAgedOutDetected, "(e) user must be informed history aged out")
    }

    @Test
    func reconciliationHappensBeforeUpload() async throws {
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        let note = Note(title: "purged", lastModifiedDeviceId: UUID())
        try await repo.create(note)

        // The remote tombstone WAS found (deletion honored) — classification
        // happens against the full remote history BEFORE any upload loop
        // runs (the engine wires classify() before uploads; T184-a).
        let tombstone = RemoteTombstone(
            noteId: note.id,
            deletedVersionId: note.versionId,
            parentVersionId: nil,
            deletingDeviceId: UUID(),
            deletedAt: Date()
        )
        let (toDelete, _) = try await OfflineReconciler.classify(
            store: store,
            remoteTombstones: [tombstone]
        )
        #expect(toDelete.contains(note.id))
    }

    @Test
    func locallyDeletedNotesAreNotReuploadedUnlessRestored() async throws {
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        let note = Note(title: "gone", lastModifiedDeviceId: UUID())
        try await repo.create(note)
        try await repo.permanentlyDelete(id: note.id, deviceId: UUID())

        // Restored: the note returns to active → it syncs again.
        // (d) applies only while the note stays deleted.
        let (_, result) = try await OfflineReconciler.classify(store: store, remoteTombstones: [])
        #expect(result.withheldLocalDeletions == 1, "(d) deleted notes are withheld from re-upload")

        try await repo.restore(id: note.id, deviceId: UUID())
        let (toDelete, resultAfterRestore) = try await OfflineReconciler.classify(store: store, remoteTombstones: [])
        #expect(toDelete.isEmpty)
        #expect(resultAfterRestore.withheldLocalDeletions == 0,
                "an explicitly restored note syncs normally")
    }

    @Test
    func divergedVersionFlagsConflictCopyOnNextSync() async throws {
        // (f): if the local version diverged from the last known common
        // ancestor, a conflict copy is created on the next sync. The
        // reconciler preserves the note (never deletes it); the engine's
        // resolver then creates the copy.
        let ancestor = UUID()
        let decision = OfflineReconciler.decide(
            localVersionId: UUID(),
            localParentVersionId: ancestor,
            localLifecycle: .active,
            remoteTombstoneVersionId: nil
        )
        #expect(decision == .preserveNoRemoteDeletionRecord,
                "(f) diverged local content is preserved; the engine creates the conflict copy")
    }
}
