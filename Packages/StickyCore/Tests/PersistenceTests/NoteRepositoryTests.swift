import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

// MARK: - NoteRepository tests (T030)
//
// Per tasks.md T030: "Implement SQLite repository for Note + Block (CRUD,
// ordering) in `Packages/StickyCore/Sources/Persistence/Repositories/
// NoteRepository.swift`."
//
// Verifies:
// - create + fetch round-trips a Note's synced fields.
// - fetchAll filters by lifecycle state and sorts by each NoteSortKey.
// - update bumps version lineage (parentVersionId = prior versionId, new
//   versionId, modifiedAt advances).
// - trash sets lifecycleState = .trashed + trashedAt.
// - restore clears trashedAt and returns to .active.
// - permanentlyDelete sets lifecycleState = .permanentlyDeleted and inserts
//   a Tombstone (sync-safety).
// - updateSortKey persists the new sort key.
// - Block CRUD: insert, fetchBlocks ordered by sortKey, update, delete.
// - Deleting the cover screenshot block nulls note.coverScreenshotBlockId
//   (the FK is app-enforced per m0001 comment).
//
// Constitution XII: tests are mandatory.

@Suite struct NoteRepositoryTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    // MARK: - Helpers

    /// Fresh DB with v1 schema + a SQLiteNoteRepository backed by it.
    private func freshRepo() async throws -> (SQLiteNoteRepository, DatabaseStore) {
        let store = try DatabaseStore.inMemory()
        let migrator = InitialSchema.migrator()
        try migrator.migrate(store.dbPool)
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        return (repo, store)
    }

    // MARK: - Note CRUD

    @Test
    func createAndFetchRoundTripsSyncedFields() async throws {
        let (repo, _) = try await freshRepo()
        let noteId = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let note = Note(
            id: noteId,
            title: "Hello",
            colorKey: .pink,
            customColor: nil,
            transparency: 0.25,
            textSize: 18,
            alwaysOnTop: true,
            widgetEligible: true,
            manualSortKey: 1024,
            lastModifiedDeviceId: Self.deviceId,
            createdAt: now,
            modifiedAt: now
        )

        try await repo.create(note)

        let fetched = try await repo.fetch(id: noteId)
        #expect(fetched != nil)
        #expect(fetched?.id == noteId)
        #expect(fetched?.title == "Hello")
        #expect(fetched?.colorKey == .pink)
        #expect(fetched?.transparency == 0.25)
        #expect(fetched?.textSize == 18)
        #expect(fetched?.alwaysOnTop == true)
        #expect(fetched?.manualSortKey == 1024)
        #expect(fetched?.lifecycleState == .active)
    }

    @Test
    func fetchAllFiltersByLifecycleAndSortsByModified() async throws {
        let (repo, _) = try await freshRepo()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // Three active notes with different modifiedAt, plus one trashed.
        let n1 = Note(id: UUID(), title: "a", manualSortKey: 0, lastModifiedDeviceId: Self.deviceId, createdAt: base, modifiedAt: base.addingTimeInterval(10))
        let n2 = Note(id: UUID(), title: "b", manualSortKey: 1024, lastModifiedDeviceId: Self.deviceId, createdAt: base, modifiedAt: base.addingTimeInterval(30))
        let n3 = Note(id: UUID(), title: "c", manualSortKey: 2048, lastModifiedDeviceId: Self.deviceId, createdAt: base, modifiedAt: base.addingTimeInterval(20))
        let n4 = Note(id: UUID(), title: "trashed", manualSortKey: 0, lastModifiedDeviceId: Self.deviceId, createdAt: base, modifiedAt: base)
        try await repo.create(n1)
        try await repo.create(n2)
        try await repo.create(n3)
        try await repo.create(n4)
        try await repo.trash(id: n4.id, deviceId: Self.deviceId)

        let active = try await repo.fetchAll(lifecycle: .active, sort: .modified)
        #expect(active.count == 3)
        // modifiedAt DESC: n2 (30) → n3 (20) → n1 (10)
        #expect(active.map(\.id) == [n2.id, n3.id, n1.id])

        let trashed = try await repo.fetchAll(lifecycle: .trashed, sort: .modified)
        #expect(trashed.count == 1)
        #expect(trashed.first?.id == n4.id)
    }

    @Test
    func fetchAllSortsByCreatedTitleAndManual() async throws {
        let (repo, _) = try await freshRepo()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let n1 = Note(id: UUID(), title: "Banana", manualSortKey: 2048, lastModifiedDeviceId: Self.deviceId, createdAt: base.addingTimeInterval(5))
        let n2 = Note(id: UUID(), title: "Apple",  manualSortKey: 0,    lastModifiedDeviceId: Self.deviceId, createdAt: base.addingTimeInterval(10))
        let n3 = Note(id: UUID(), title: "Cherry", manualSortKey: 1024, lastModifiedDeviceId: Self.deviceId, createdAt: base)
        try await repo.create(n1); try await repo.create(n2); try await repo.create(n3)

        let byCreated = try await repo.fetchAll(lifecycle: .active, sort: .created)
        #expect(byCreated.map(\.id) == [n2.id, n1.id, n3.id])  // createdAt DESC

        let byTitle = try await repo.fetchAll(lifecycle: .active, sort: .title)
        #expect(byTitle.map(\.title) == ["Apple", "Banana", "Cherry"])

        let byManual = try await repo.fetchAll(lifecycle: .active, sort: .manual)
        #expect(byManual.map(\.manualSortKey) == [0, 1024, 2048])
    }

    @Test
    func updateBumpsVersionLineage() async throws {
        let (repo, _) = try await freshRepo()
        let noteId = UUID()
        let note = Note(id: noteId, title: "orig", lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        let original = try await repo.fetch(id: noteId)!
        var updated = original
        updated.title = "edited"
        try await repo.update(updated, modifyingDeviceId: Self.deviceId)

        let fetched = try await repo.fetch(id: noteId)!
        #expect(fetched.title == "edited")
        #expect(fetched.versionId != original.versionId)
        #expect(fetched.parentVersionId == original.versionId)
        #expect(fetched.modifiedAt >= original.modifiedAt)
    }

    @Test
    func trashAndRestoreCycle() async throws {
        let (repo, _) = try await freshRepo()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))

        try await repo.trash(id: noteId, deviceId: Self.deviceId)
        let trashed = try await repo.fetch(id: noteId)!
        #expect(trashed.lifecycleState == .trashed)
        #expect(trashed.trashedAt != nil)

        try await repo.restore(id: noteId, deviceId: Self.deviceId)
        let restored = try await repo.fetch(id: noteId)!
        #expect(restored.lifecycleState == .active)
        #expect(restored.trashedAt == nil)
    }

    @Test
    func permanentlyDeleteSetsLifecycleAndCreatesTombstone() async throws {
        let (repo, store) = try await freshRepo()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))

        try await repo.permanentlyDelete(id: noteId, deviceId: Self.deviceId)

        let fetched = try await repo.fetch(id: noteId)
        #expect(fetched?.lifecycleState == .permanentlyDeleted)

        // Tombstone row exists.
        let tombstoneCount: Int = try await store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tombstone WHERE noteId = ?",
                             arguments: [noteId.uuidString]) ?? 0
        }
        #expect(tombstoneCount == 1)
    }

    @Test
    func updateSortKeyPersists() async throws {
        let (repo, _) = try await freshRepo()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, manualSortKey: 0, lastModifiedDeviceId: Self.deviceId))

        try await repo.updateSortKey(id: noteId, sortKey: 5000, deviceId: Self.deviceId)
        let fetched = try await repo.fetch(id: noteId)!
        #expect(fetched.manualSortKey == 5000)
    }

    // MARK: - Block CRUD

    @Test
    func blockInsertFetchOrderedBySortKey() async throws {
        let (repo, _) = try await freshRepo()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))

        let b1 = Block(noteId: noteId, kind: .richText, sortKey: 2048, payload: .richText(RichTextDocument.plain("c")), lastModifiedDeviceId: Self.deviceId)
        let b2 = Block(noteId: noteId, kind: .richText, sortKey: 0,    payload: .richText(RichTextDocument.plain("a")), lastModifiedDeviceId: Self.deviceId)
        let b3 = Block(noteId: noteId, kind: .richText, sortKey: 1024, payload: .richText(RichTextDocument.plain("b")), lastModifiedDeviceId: Self.deviceId)
        try await repo.insertBlock(b1)
        try await repo.insertBlock(b2)
        try await repo.insertBlock(b3)

        let blocks = try await repo.fetchBlocks(noteId: noteId)
        #expect(blocks.count == 3)
        #expect(blocks.map(\.sortKey) == [0, 1024, 2048])
        #expect(blocks.map { $0.payload }.map { p -> String? in
            if case .richText(let doc) = p { return doc.text } else { return nil }
        } == ["a", "b", "c"])
    }

    @Test
    func blockUpdateBumpsLineage() async throws {
        let (repo, _) = try await freshRepo()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))
        let block = Block(noteId: noteId, kind: .code, sortKey: 0, payload: .code(CodePayload(text: "print(1)")), lastModifiedDeviceId: Self.deviceId)
        try await repo.insertBlock(block)

        var fetched = try await repo.fetchBlocks(noteId: noteId).first!
        let originalVersion = fetched.versionId
        fetched.payload = .code(CodePayload(text: "print(2)"))
        try await repo.updateBlock(fetched, modifyingDeviceId: Self.deviceId)

        let after = try await repo.fetchBlocks(noteId: noteId).first!
        #expect(after.versionId != originalVersion)
        #expect(after.parentVersionId == originalVersion)
    }

    @Test
    func blockDeleteRemovesRow() async throws {
        let (repo, _) = try await freshRepo()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))
        let block = Block(noteId: noteId, kind: .code, sortKey: 0, payload: .code(CodePayload(text: "x")), lastModifiedDeviceId: Self.deviceId)
        try await repo.insertBlock(block)

        try await repo.deleteBlock(id: block.id)
        let blocks = try await repo.fetchBlocks(noteId: noteId)
        #expect(blocks.isEmpty)
    }

    @Test
    func deletingCoverScreenshotBlockNullsNoteCover() async throws {
        let (repo, store) = try await freshRepo()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))
        let block = Block(noteId: noteId, kind: .screenshot, sortKey: 0, payload: .screenshot(ScreenshotPayload(originalAssetId: UUID(), thumbnailAssetId: UUID(), capturedAt: Date(), isCover: true)), lastModifiedDeviceId: Self.deviceId)
        try await repo.insertBlock(block)

        // Set the cover reference.
        try await store.write { db in
            try db.execute(sql: "UPDATE note SET coverScreenshotBlockId = ? WHERE id = ?",
                           arguments: [block.id.uuidString, noteId.uuidString])
        }
        let before = try await repo.fetch(id: noteId)!
        #expect(before.coverScreenshotBlockId == block.id)

        // Deleting the cover block should null the note's reference.
        try await repo.deleteBlock(id: block.id)
        let after = try await repo.fetch(id: noteId)!
        #expect(after.coverScreenshotBlockId == nil)
    }

    // MARK: - Search document maintenance

    @Test
    func createNoteWritesEmptySearchDocument() async throws {
        let (repo, store) = try await freshRepo()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, title: "Searchable Title", lastModifiedDeviceId: Self.deviceId))

        let count: Int = try await store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_fts_content WHERE noteId = ?",
                             arguments: [noteId.uuidString]) ?? 0
        }
        #expect(count == 1, "NoteRepository.create should write an FTS content row")
    }
}
