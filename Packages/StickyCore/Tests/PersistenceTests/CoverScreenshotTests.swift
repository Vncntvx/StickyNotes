import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

// MARK: - Cover screenshot nullification tests (T260, FR-094b)
//
// Per tasks.md T260: "Persistence test: cover-screenshot nullification per
// FR-094b — create a note with two screenshot blocks, select one as the card
// cover, delete that block: assert `Note.coverScreenshotBlockId` is
// nullified within the same transaction (FK ON DELETE SET NULL DEFERRABLE
// INITIALLY DEFERRED, T152), no dangling reference is ever observable, and
// the note card falls back to a no-cover state with no extra confirmation".

@Suite struct CoverScreenshotTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    private func freshRepo() async throws -> (SQLiteNoteRepository, DatabaseStore) {
        let store = try DatabaseStore.inMemory()
        let migrator = InitialSchema.migrator()
        try migrator.migrate(store.dbPool)
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        return (repo, store)
    }

    private func screenshotBlock(noteId: UUID, sortKey: Int) -> Block {
        Block(
            noteId: noteId,
            kind: .screenshot,
            sortKey: sortKey,
            payload: .screenshot(ScreenshotPayload(
                originalAssetId: UUID(),
                thumbnailAssetId: UUID(),
                capturedAt: Date()
            )),
            lastModifiedDeviceId: Self.deviceId
        )
    }

    @Test
    func deletingCoverScreenshotNullifiesReferenceTransactionally() async throws {
        let (repo, _) = try await freshRepo()
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        let coverBlock = screenshotBlock(noteId: note.id, sortKey: 0)
        let otherBlock = screenshotBlock(noteId: note.id, sortKey: 1024)
        try await repo.insert(coverBlock)
        try await repo.insert(otherBlock)

        // Select the first block as the cover.
        var withCover = note
        withCover.coverScreenshotBlockId = coverBlock.id
        try await repo.update(withCover, modifyingDeviceId: Self.deviceId)

        // Cover is set.
        let before = try await repo.fetch(id: note.id)
        #expect(before?.coverScreenshotBlockId == coverBlock.id)

        // Delete the cover block: the FK (ON DELETE SET NULL DEFERRABLE
        // INITIALLY DEFERRED, T152) nulls the reference in the same
        // transaction — no dangling reference is ever observable.
        try await repo.delete(id: coverBlock.id)

        let after = try await repo.fetch(id: note.id)
        #expect(after?.coverScreenshotBlockId == nil, "cover reference must be nullified")

        // No dangling reference anywhere: the block is gone.
        let blocks = try await repo.fetchBlocks(noteId: note.id)
        #expect(blocks.count == 1)
        #expect(blocks.first?.id == otherBlock.id)
    }

    @Test
    func deletingNonCoverScreenshotKeepsCover() async throws {
        let (repo, _) = try await freshRepo()
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        let coverBlock = screenshotBlock(noteId: note.id, sortKey: 0)
        let otherBlock = screenshotBlock(noteId: note.id, sortKey: 1024)
        try await repo.insert(coverBlock)
        try await repo.insert(otherBlock)

        var withCover = note
        withCover.coverScreenshotBlockId = coverBlock.id
        try await repo.update(withCover, modifyingDeviceId: Self.deviceId)

        try await repo.delete(id: otherBlock.id)

        let after = try await repo.fetch(id: note.id)
        #expect(after?.coverScreenshotBlockId == coverBlock.id, "non-cover deletion must not affect the cover")
    }

    @Test
    func cardProjectionFallsBackToNoCoverState() async throws {
        let (repo, store) = try await freshRepo()
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        let coverBlock = screenshotBlock(noteId: note.id, sortKey: 0)
        try await repo.insert(coverBlock)
        var withCover = note
        withCover.coverScreenshotBlockId = coverBlock.id
        try await repo.update(withCover, modifyingDeviceId: Self.deviceId)

        try await repo.delete(id: coverBlock.id)

        // The card grid renders from projections; a nulled cover simply
        // means no cover thumbnail is requested (no-cover fallback, no
        // confirmation dialog — FR-094b).
        let projections = try await CardProjection.fetchCardProjections(
            store: store,
            lifecycle: .active,
            sort: .modified
        )
        #expect(projections.count == 1)
        let projection = projections.first!
        #expect(projection.hasScreenshot == false, "cover block was the only screenshot; indicator must be false after deletion")
    }
}
