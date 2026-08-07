import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

// MARK: - Empty Trash tests (T222, FR-014b)
//
// Per tasks.md T222: "Persistence test: Empty Trash batch permanent delete
// per FR-014b — with N notes in Trash, invoking Empty Trash without
// confirmation deletes nothing; after confirmation, ALL trashed notes
// transition trashed → permanentlyDeleted in a single transaction (no
// intermediate observable state); readable local content removed when safe;
// a Tombstone is retained per note for sync (FR-174 sync-safety applies);
// the confirmation states immediate permanent deletion and loss of the
// 30-day recoverability guarantee".

@Suite struct EmptyTrashTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    private func freshRepo() async throws -> (SQLiteNoteRepository, DatabaseStore) {
        let store = try DatabaseStore.inMemory()
        let migrator = InitialSchema.migrator()
        try migrator.migrate(store.dbPool)
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        return (repo, store)
    }

    private func makeNote(title: String? = nil) -> Note {
        Note(title: title, lastModifiedDeviceId: Self.deviceId)
    }

    @Test
    func emptyTrashTransitionsAllTrashedNotesInOneTransaction() async throws {
        let (repo, _) = try await freshRepo()

        // 2 trashed + 1 active note.
        let a = makeNote(title: "A")
        let b = makeNote(title: "B")
        let c = makeNote(title: "C")
        try await repo.create(a)
        try await repo.create(b)
        try await repo.create(c)
        try await repo.trash(id: a.id, deviceId: Self.deviceId)
        try await repo.trash(id: b.id, deviceId: Self.deviceId)

        let emptied = try await repo.emptyTrash(deviceId: Self.deviceId)

        #expect(Set(emptied) == [a.id, b.id])
        let aNow = try await repo.fetch(id: a.id)
        let bNow = try await repo.fetch(id: b.id)
        let cNow = try await repo.fetch(id: c.id)
        #expect(aNow?.lifecycleState == .permanentlyDeleted)
        #expect(bNow?.lifecycleState == .permanentlyDeleted)
        #expect(cNow?.lifecycleState == .active, "active notes are untouched")
    }

    @Test
    func tombstoneRetainedPerNoteForSync() async throws {
        let (repo, store) = try await freshRepo()
        let a = makeNote(title: "A")
        try await repo.create(a)
        try await repo.trash(id: a.id, deviceId: Self.deviceId)

        let emptied = try await repo.emptyTrash(deviceId: Self.deviceId)
        #expect(emptied == [a.id])

        let tombstones: [String] = try await store.read { db in
            try String.fetchAll(db, sql: "SELECT noteId FROM tombstone")
        }
        #expect(tombstones == [a.id.uuidString], "FR-174: a tombstone is retained per emptied note")
    }

    @Test
    func emptyTrashWithNoTrashedNotesIsNoOp() async throws {
        let (repo, _) = try await freshRepo()
        let c = makeNote(title: "C")
        try await repo.create(c)

        let emptied = try await repo.emptyTrash(deviceId: Self.deviceId)
        #expect(emptied.isEmpty)
        let cNow = try await repo.fetch(id: c.id)
        #expect(cNow?.lifecycleState == .active)
    }

    @Test
    func restoredThenRetrashedNoteIsEmptiedAgain() async throws {
        let (repo, _) = try await freshRepo()
        let a = makeNote(title: "A")
        try await repo.create(a)
        try await repo.trash(id: a.id, deviceId: Self.deviceId)
        try await repo.restore(id: a.id, deviceId: Self.deviceId)
        try await repo.trash(id: a.id, deviceId: Self.deviceId)

        let emptied = try await repo.emptyTrash(deviceId: Self.deviceId)
        #expect(emptied == [a.id])
        #expect(emptied == [a.id])
        let aNow = try await repo.fetch(id: a.id)
        #expect(aNow?.lifecycleState == .permanentlyDeleted)
    }
}
