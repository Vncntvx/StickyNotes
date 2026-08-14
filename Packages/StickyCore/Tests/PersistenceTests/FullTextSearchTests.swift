import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

// MARK: - FTS5 indexing + search tests (T038)
//
// Per tasks.md T038: "Persistence test: FTS5 indexes title/summary/body/
// todos/code/fileNames/captions and updates transactionally."
//
// Verifies:
// - The SearchService.buildSearchDocument projection extracts every column
//   from a note + its blocks.
// - reindexNote writes the projection so a MATCH query finds the note.
// - Searching for a word appearing only in: title / body / todo / code /
//   file name / caption each return the matching note.
// - Notes outside the active lifecycle are NEVER returned.
// - Trashed notes are excluded from the active scope but appear in the
//   Trash scope.
// - Removing a note's search document makes it unfindable.

@Suite struct FullTextSearchTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    // MARK: - Helpers

    private func freshServices() async throws -> (SQLiteNoteRepository, SearchService, DatabaseStore) {
        let store = try DatabaseStore.inMemory()
        let migrator = InitialSchema.migrator()
        try migrator.migrate(store.dbPool)
        let fts = FullTextSearch(dbPool: store.dbPool)
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: fts)
        let search = SearchService(store: store, fullTextSearch: fts)
        return (repo, search, store)
    }

    // MARK: - SearchDocument projection (pure)

    @Test
    func buildSearchDocumentExtractsEveryColumn() async throws {
        let noteId = UUID()
        let blocks: [Block] = [
            Block(noteId: noteId, kind: .richText, sortKey: 0,
                  payload: .richText(RichTextDocument.plain("body keyword here")),
                  lastModifiedDeviceId: Self.deviceId),
            Block(noteId: noteId, kind: .todo, sortKey: 1024,
                  payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("todo keyword"))),
                  lastModifiedDeviceId: Self.deviceId),
            Block(noteId: noteId, kind: .code, sortKey: 2048,
                  payload: .code(CodePayload(text: "code keyword")),
                  lastModifiedDeviceId: Self.deviceId),
            Block(noteId: noteId, kind: .fileRef, sortKey: 3072,
                  payload: .fileReference(FileReferencePayload(displayName: "filename.pdf", contentType: "com.adobe.pdf", originDeviceId: Self.deviceId, addedAt: Date(), caption: "file caption keyword")),
                  lastModifiedDeviceId: Self.deviceId),
            Block(noteId: noteId, kind: .screenshot, sortKey: 4096,
                  payload: .screenshot(ScreenshotPayload(originalAssetId: UUID(), thumbnailAssetId: UUID(), caption: "screenshot caption keyword", capturedAt: Date())),
                  lastModifiedDeviceId: Self.deviceId),
        ]

        // We only need the projection here; build a SearchService backed
        // by a throwaway in-memory pool solely to exercise buildSearchDocument.
        let store = try DatabaseStore.inMemory()
        let fts = FullTextSearch(dbPool: store.dbPool)
        let search = SearchService(store: store, fullTextSearch: fts)
        let doc = search.buildSearchDocument(noteId: noteId, title: "title keyword", blocks: blocks)

        #expect(doc.title == "title keyword")
        #expect(doc.body.contains("body"))
        #expect(doc.todos.contains("todo"))
        #expect(doc.code.contains("code"))
        #expect(doc.fileNames.contains("filename.pdf"))
        #expect(doc.captions.contains("screenshot caption keyword"))
        #expect(doc.summary == "body keyword here")  // first meaningful block
    }

    // MARK: - Transactional indexing + MATCH queries per column

    @Test
    func searchFindsByTitle() async throws {
        let (repo, search, _) = try await freshServices()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, title: "Quarterly Report", lastModifiedDeviceId: Self.deviceId))
        try await search.reindexNote(noteId: noteId, title: "Quarterly Report", blocks: [])

        let hits = try await search.searchActiveNotes(query: "Quarterly")
        #expect(hits.contains(where: { $0.id == noteId }))
    }

    @Test
    func searchFindsByBody() async throws {
        let (repo, search, _) = try await freshServices()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))
        let blocks = [Block(noteId: noteId, kind: .richText, sortKey: 0, payload: .richText(RichTextDocument.plain("deep body content with rareword")), lastModifiedDeviceId: Self.deviceId)]
        try await search.reindexNote(noteId: noteId, title: nil, blocks: blocks)

        let hits = try await search.searchActiveNotes(query: "rareword")
        #expect(hits.contains(where: { $0.id == noteId }))
    }

    @Test
    func searchFindsByTodo() async throws {
        let (repo, search, _) = try await freshServices()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))
        let blocks = [Block(noteId: noteId, kind: .todo, sortKey: 0, payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("pick up zucchini"))), lastModifiedDeviceId: Self.deviceId)]
        try await search.reindexNote(noteId: noteId, title: nil, blocks: blocks)

        let hits = try await search.searchActiveNotes(query: "zucchini")
        #expect(hits.contains(where: { $0.id == noteId }))
    }

    @Test
    func searchFindsByCode() async throws {
        let (repo, search, _) = try await freshServices()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))
        let blocks = [Block(noteId: noteId, kind: .code, sortKey: 0, payload: .code(CodePayload(text: "func fluxgate()")), lastModifiedDeviceId: Self.deviceId)]
        try await search.reindexNote(noteId: noteId, title: nil, blocks: blocks)

        let hits = try await search.searchActiveNotes(query: "fluxgate")
        #expect(hits.contains(where: { $0.id == noteId }))
    }

    // MARK: - R1.4 FTS update atomicity (remediation roadmap 2026-08-14)

    /// `NoteRepository.update` refreshes the FTS title via `upsertSearchRow`,
    /// whose `ON CONFLICT DO UPDATE` replaces EVERY column — the audit
    /// found it passes empty body/todos/code, so any `update()` that is
    /// not immediately followed by a reindex silently destroys the note's
    /// searchability (the app's host layer happened to reindex, masking
    /// the defect). A plain metadata update must not wipe searchable
    /// content.
    @Test
    func updatePreservesSearchableBody() async throws {
        let (repo, search, _) = try await freshServices()
        let noteId = UUID()
        var note = Note(id: noteId, lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)
        let blocks = [Block(noteId: noteId, kind: .richText, sortKey: 0,
                            payload: .richText(RichTextDocument.plain("unique body token xylophone")),
                            lastModifiedDeviceId: Self.deviceId)]
        try await search.reindexNote(noteId: noteId, title: "Hello", blocks: blocks)
        #expect(try await search.searchActiveNotes(query: "xylophone").contains { $0.id == noteId },
                "precondition: the body token is searchable before the update")

        // A metadata-only update (title change, no content change) — the
        // shape every autosave/version bump takes.
        note.title = "Renamed"
        try await repo.update(note, modifyingDeviceId: Self.deviceId)

        let hits = try await search.searchActiveNotes(query: "xylophone")
        #expect(hits.contains { $0.id == noteId },
                "update() must not wipe searchable body content (got \(hits.map(\.id)))")
    }

    @Test
    func searchFindsByFileName() async throws {
        let (repo, search, _) = try await freshServices()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))
        let blocks = [Block(noteId: noteId, kind: .fileRef, sortKey: 0, payload: .fileReference(FileReferencePayload(displayName: "megaschema.sql", contentType: "public.sql", originDeviceId: Self.deviceId, addedAt: Date())), lastModifiedDeviceId: Self.deviceId)]
        try await search.reindexNote(noteId: noteId, title: nil, blocks: blocks)

        let hits = try await search.searchActiveNotes(query: "megaschema")
        #expect(hits.contains(where: { $0.id == noteId }))
    }

    @Test
    func searchFindsByCaption() async throws {
        let (repo, search, _) = try await freshServices()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))
        let blocks = [Block(noteId: noteId, kind: .screenshot, sortKey: 0, payload: .screenshot(ScreenshotPayload(originalAssetId: UUID(), thumbnailAssetId: UUID(), caption: "kerfuffle trace", capturedAt: Date())), lastModifiedDeviceId: Self.deviceId)]
        try await search.reindexNote(noteId: noteId, title: nil, blocks: blocks)

        let hits = try await search.searchActiveNotes(query: "kerfuffle")
        #expect(hits.contains(where: { $0.id == noteId }))
    }

    // MARK: - Privacy + lifecycle scope

    @Test
    func nonActiveLifecycleNotesAreNeverReturned() async throws {
        let (repo, search, _) = try await freshServices()
        let noteId = UUID()
        var note = Note(id: noteId, title: "HiddenPlanner", lastModifiedDeviceId: Self.deviceId)
        note.lifecycleState = .permanentlyDeleted
        try await repo.create(note)

        let hits = try await search.searchActiveNotes(query: "HiddenPlanner")
        #expect(!hits.contains(where: { $0.id == noteId }), "non-active lifecycle notes must never appear in active search")
    }

    @Test
    func trashedNotesExcludedFromActiveButFoundInTrash() async throws {
        let (repo, search, _) = try await freshServices()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, title: "TrashedFindable", lastModifiedDeviceId: Self.deviceId))
        try await repo.trash(id: noteId, deviceId: Self.deviceId)

        let activeHits = try await search.searchActiveNotes(query: "TrashedFindable")
        #expect(!activeHits.contains(where: { $0.id == noteId }))

        let trashHits = try await search.searchTrashedNotes(query: "TrashedFindable")
        #expect(trashHits.contains(where: { $0.id == noteId }))
    }

    @Test
    func removingNoteFromIndexMakesItUnfindable() async throws {
        let (repo, search, _) = try await freshServices()
        let noteId = UUID()
        try await repo.create(Note(id: noteId, title: "GoneSoon", lastModifiedDeviceId: Self.deviceId))

        try await search.removeNote(noteId: noteId)
        let hits = try await search.searchActiveNotes(query: "GoneSoon")
        #expect(!hits.contains(where: { $0.id == noteId }))
    }

    @Test
    func emptyQueryReturnsNoResults() async throws {
        let (_, search, _) = try await freshServices()
        let hits = try await search.searchActiveNotes(query: "   ")
        #expect(hits.isEmpty)
    }
}
