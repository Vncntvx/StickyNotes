import Testing
import Foundation
import GRDB
import Domain
import Persistence

// MARK: - Trash-restore sort-key reset tests (T214, FR-022a clarified 2026-08-07)
//
// Per tasks.md T214: delete a note from the middle of Manual order (sort-key
// S_mid); insert a new note (which may reuse the freed position); restore the
// deleted note → the restored note's manualSortKey equals (max(active sort-key)
// + 1024), NOT S_mid; it appears at the end of Manual order; no renormalization
// is triggered by restore alone (the new key is strictly greater than all
// existing keys); ordering of other notes is unchanged.

@Suite struct TrashRestoreSortKeyTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000003")!

    private func makeStore() throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    private func makeNote(sortKey: Int) -> Note {
        Note(manualSortKey: sortKey, lastModifiedDeviceId: Self.deviceId)
    }

    @Test
    func restoreResetsSortKeyToMaxActivePlus1024() async throws {
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))

        // Three notes in Manual order: 0, 1024, 2048.
        let noteA = makeNote(sortKey: 0)
        let noteB = makeNote(sortKey: 1024)
        let noteC = makeNote(sortKey: 2048)
        try await repo.create(noteA)
        try await repo.create(noteB)
        try await repo.create(noteC)

        // Delete noteB (sort-key 1024 — the middle).
        try await repo.trash(id: noteB.id, deviceId: Self.deviceId)

        // Restore noteB → its sort-key should be (max active + 1024) = 2048 + 1024 = 3072.
        try await repo.restore(id: noteB.id, deviceId: Self.deviceId)

        let restored = try await repo.fetch(id: noteB.id)
        #expect(restored?.lifecycleState == .active)
        #expect(restored?.manualSortKey == 3072, "restored note must be at end (max+1024); got \(restored?.manualSortKey ?? -1)")
    }

    @Test
    func restoreDoesNotRetainPreDeletionSortKey() async throws {
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))

        // Three notes so the restored key differs from the pre-deletion key.
        let noteA = makeNote(sortKey: 0)
        let noteB = makeNote(sortKey: 1024)
        let noteC = makeNote(sortKey: 2048)
        try await repo.create(noteA)
        try await repo.create(noteB)
        try await repo.create(noteC)

        // Delete noteB (sort-key 1024).
        try await repo.trash(id: noteB.id, deviceId: Self.deviceId)

        // Restore noteB → its sort-key must NOT be 1024 (the pre-deletion key).
        try await repo.restore(id: noteB.id, deviceId: Self.deviceId)
        let restored = try await repo.fetch(id: noteB.id)
        #expect(restored?.manualSortKey != 1024, "pre-deletion sort-key must NOT be retained")
        // max(active) = max(0, 2048) = 2048; restored = 2048 + 1024 = 3072.
        #expect(restored?.manualSortKey == 3072, "restored note at max+1024 = 3072")
    }

    @Test
    func restoreAloneTriggersNoRenormalization() async throws {
        // The restored key is strictly greater than all existing keys, so
        // restore alone never triggers renormalization (gap never drops
        // below 64 — the new key is exactly 1024 above the max).
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))

        let noteA = makeNote(sortKey: 0)
        let noteB = makeNote(sortKey: 1024)
        try await repo.create(noteA)
        try await repo.create(noteB)

        try await repo.trash(id: noteB.id, deviceId: Self.deviceId)
        try await repo.restore(id: noteB.id, deviceId: Self.deviceId)

        let restored = try await repo.fetch(id: noteB.id)
        // The gap between noteA (0) and the restored noteB (2048) is 2048 —
        // well above the 64 threshold. No renormalization needed.
        #expect(restored!.manualSortKey - noteA.manualSortKey >= ManualSortKeys.normalizationThreshold)
    }

    @Test
    func restorePreservesOtherNotesOrdering() async throws {
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))

        let noteA = makeNote(sortKey: 0)
        let noteB = makeNote(sortKey: 1024)
        let noteC = makeNote(sortKey: 2048)
        try await repo.create(noteA)
        try await repo.create(noteB)
        try await repo.create(noteC)

        // Delete and restore noteB.
        try await repo.trash(id: noteB.id, deviceId: Self.deviceId)
        try await repo.restore(id: noteB.id, deviceId: Self.deviceId)

        // noteA and noteC keep their original sort-keys.
        let fetchedA = try await repo.fetch(id: noteA.id)
        let fetchedC = try await repo.fetch(id: noteC.id)
        #expect(fetchedA?.manualSortKey == 0)
        #expect(fetchedC?.manualSortKey == 2048)

        // Manual order: noteA (0), noteC (2048), noteB (3072 — restored to end).
        let active = try await repo.fetchAll(lifecycle: .active, sort: .manual)
        #expect(active.map(\.id) == [noteA.id, noteC.id, noteB.id])
    }

    @Test
    func restoreAfterInsertingIntoFreedPositionStillGoesToEnd() async throws {
        // Insert a new note (which may reuse the freed position) after
        // deleting; restore the deleted note → it still goes to the end.
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))

        let noteA = makeNote(sortKey: 0)
        let noteB = makeNote(sortKey: 1024)
        try await repo.create(noteA)
        try await repo.create(noteB)

        // Delete noteB (sort-key 1024).
        try await repo.trash(id: noteB.id, deviceId: Self.deviceId)

        // Insert a new note at sort-key 1024 (reusing the freed position).
        let noteD = makeNote(sortKey: 1024)
        try await repo.create(noteD)

        // Restore noteB → it goes to max(0, 1024, 1024) + 1024 = 2048.
        try await repo.restore(id: noteB.id, deviceId: Self.deviceId)
        let restored = try await repo.fetch(id: noteB.id)
        #expect(restored?.manualSortKey == 2048, "restored note at end even after a new note reused the freed position")
    }
}
