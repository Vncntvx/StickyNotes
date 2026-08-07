import Testing
import Foundation
import Domain
import Persistence
import SecurityCore
import SyncCore

// MARK: - Tombstone lifecycle tests (T163m / T123, US10)
//
// Per tasks.md T163m: "tombstone lifecycle (offline <30d, >30d, device
// returning after remote cleanup, unknown devices, manual Trash empty)".

@Suite struct TombstoneTests {

    private func makeStore() throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    /// Creates a note row (the tombstone table's FK requires one).
    private func makeNote(_ store: DatabaseStore, title: String = "t") async throws -> UUID {
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        let note = Note(title: title, lastModifiedDeviceId: UUID())
        try await repo.create(note)
        return note.id
    }

    private func tombstone(noteId: UUID, deletedAt: Date, canPurgeRemote: Bool = true) -> Tombstone {
        Tombstone(
            noteId: noteId,
            deletedVersionId: UUID(),
            deletingDeviceId: UUID(),
            deletedAt: deletedAt,
            canPurgeRemote: canPurgeRemote
        )
    }

    @Test
    func recordAndFetchRoundTrip() async throws {
        let store = try makeStore()
        let repo = SQLiteTombstoneRepository(store: store)
        let noteId = try await makeNote(store)
        let stone = tombstone(noteId: noteId, deletedAt: Date())
        try await repo.record(stone)

        let fetched = try await repo.fetch(noteId: stone.noteId)
        #expect(fetched != nil)
        #expect(fetched?.noteId == stone.noteId)
        #expect(fetched?.deletedVersionId == stone.deletedVersionId)
    }

    @Test
    func purgeKeepsTombstonesWithinRetentionWindow() async throws {
        let store = try makeStore()
        let repo = SQLiteTombstoneRepository(store: store)

        // Deleted 10 days ago (within 30-day retention).
        let recent = tombstone(noteId: try await makeNote(store), deletedAt: Date().addingTimeInterval(-10 * 86_400))
        // Deleted 40 days ago (outside retention) — but NOT yet sync-safe.
        let oldUnsafe = tombstone(noteId: try await makeNote(store), deletedAt: Date().addingTimeInterval(-40 * 86_400), canPurgeRemote: false)
        // Deleted 40 days ago AND sync-safe.
        let oldSafe = tombstone(noteId: try await makeNote(store), deletedAt: Date().addingTimeInterval(-40 * 86_400), canPurgeRemote: true)

        try await repo.record(recent)
        try await repo.record(oldUnsafe)
        try await repo.record(oldSafe)

        let purged = try await repo.purgeExpired(now: Date(), retentionDays: 30)
        #expect(purged == [oldSafe.noteId], "only expired + sync-safe tombstones are purged")
        #expect(try await repo.fetch(noteId: recent.noteId) != nil, "recent tombstone kept")
        #expect(try await repo.fetch(noteId: oldUnsafe.noteId) != nil, "unsafe tombstone kept (sync-safety gate)")
        #expect(try await repo.fetch(noteId: oldSafe.noteId) == nil)
    }

    @Test
    func offlineLessThanThirtyDaysKeepsTombstone() async throws {
        let store = try makeStore()
        let repo = SQLiteTombstoneRepository(store: store)
        let stone = tombstone(noteId: try await makeNote(store), deletedAt: Date().addingTimeInterval(-29 * 86_400))
        try await repo.record(stone)

        let purged = try await repo.purgeExpired(now: Date(), retentionDays: 30)
        #expect(purged.isEmpty, "an offline device returning within 30 days must still find the tombstone")
    }

    @Test
    func manualTrashEmptyDeletesTombstoneRecord() async throws {
        let store = try makeStore()
        let repo = SQLiteTombstoneRepository(store: store)
        let stone = tombstone(noteId: try await makeNote(store), deletedAt: Date())
        try await repo.record(stone)

        try await repo.delete(noteId: stone.noteId)
        #expect(try await repo.fetch(noteId: stone.noteId) == nil)
    }

    @Test
    func unknownDevicesDoNotPurgePrematurely() async throws {
        let store = try makeStore()
        let repo = SQLiteTombstoneRepository(store: store)
        // Old tombstone whose remote copy was never confirmed purgable
        // (e.g. an unknown device may still be offline).
        let stone = tombstone(noteId: try await makeNote(store), deletedAt: Date().addingTimeInterval(-45 * 86_400), canPurgeRemote: false)
        try await repo.record(stone)

        let purged = try await repo.purgeExpired(now: Date(), retentionDays: 30)
        #expect(purged.isEmpty, "sync-safety gate prevents premature purge while any device may be offline")

        // Once the engine confirms all devices saw the deletion, purge is
        // allowed.
        try await repo.markRemotePurgable(noteId: stone.noteId)
        let purgedNow = try await repo.purgeExpired(now: Date(), retentionDays: 30)
        #expect(purgedNow == [stone.noteId])
    }
}
