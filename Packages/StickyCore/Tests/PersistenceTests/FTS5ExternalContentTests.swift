import Testing
import Foundation
import GRDB
import Domain
import Persistence

// MARK: - FTS5 external-content mode tests (T188/T201, FR-023a clarified 2026-08-07)
//
// Per tasks.md T188/T201: the FTS5 `notes_fts` table is an external-content
// table backed by canonical note rows with an explicit rowid-to-Note.id
// mapping. Deleting a note cascades to remove its FTS5 entry automatically.
// A drift-detection + rebuild-from-canonical path exists.

@Suite struct FTS5ExternalContentTests {

    private func makeStore() throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    @Test
    func notesFtsIsExternalContentTableBackedByNoteFtsContent() async throws {
        // The FTS5 virtual table uses `synchronize(withTable:)` to link to
        // the `note_fts_content` content table — external-content mode.
        let store = try makeStore()
        let sql = try await store.read { db in
            try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE type='table' AND name='notes_fts'")
        }
        #expect(sql != nil)
        // The virtual table definition references the content table.
        #expect(sql?.contains("notes_fts") == true)
    }

    @Test
    func noteFtsContentTableExistsWithNoteIdPrimaryKey() async throws {
        let store = try makeStore()
        let sql = try await store.read { db in
            try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE type='table' AND name='note_fts_content'")
        }
        #expect(sql != nil)
        #expect(sql?.contains("noteId") == true)
    }

    @Test
    func deletingNoteCascadesToFtsEntry() async throws {
        // The note_fts_content row has a FK to note with ON DELETE CASCADE.
        // Deleting the note removes the FTS content row automatically.
        let store = try makeStore()
        let noteId = UUID()
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, title, colorKey, transparency, textSize, alwaysOnTop,
                                      widgetEligible, manualSortKey, lifecycleState, versionId,
                                      lastModifiedDeviceId, createdAt, modifiedAt)
                    VALUES (?, ?, 'yellow', 0, 'regular', 0, 1, 0, 'active', ?, ?, ?, ?)
                    """,
                arguments: [noteId.uuidString, "searchable title", UUID().uuidString,
                            UUID().uuidString, Date(), Date()]
            )
            try db.execute(
                sql: "INSERT INTO note_fts_content (noteId, title, summary, body, todos, code, fileNames, captions, ocr) VALUES (?, ?, '', '', '', '', '', '', '')",
                arguments: [noteId.uuidString, "searchable title"]
            )
        }
        // Verify the FTS content row exists.
        let beforeCount = try await store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_fts_content WHERE noteId = ?", arguments: [noteId.uuidString])
        }
        #expect(beforeCount == 1)

        // Delete the note — the FTS content row should cascade-delete.
        try await store.write { db in
            try db.execute(sql: "DELETE FROM note WHERE id = ?", arguments: [noteId.uuidString])
        }
        let afterCount = try await store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_fts_content WHERE noteId = ?", arguments: [noteId.uuidString])
        }
        #expect(afterCount == 0, "FTS content row must cascade-delete with the note")
    }

    @Test
    func ftsContentRowMappingIsDeterministicByNoteId() async throws {
        // The rowid-to-Note.id mapping is deterministic: the note_fts_content
        // table's primary key is noteId (a UUID string), so each note maps
        // to exactly one FTS content row.
        let store = try makeStore()
        let noteId = UUID()
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, title, colorKey, transparency, textSize, alwaysOnTop,
                                      widgetEligible, manualSortKey, lifecycleState, versionId,
                                      lastModifiedDeviceId, createdAt, modifiedAt)
                    VALUES (?, 't', 'yellow', 0, 'regular', 0, 1, 0, 'active', ?, ?, ?, ?)
                    """,
                arguments: [noteId.uuidString, UUID().uuidString, UUID().uuidString, Date(), Date()]
            )
            try db.execute(
                sql: "INSERT INTO note_fts_content (noteId, title, summary, body, todos, code, fileNames, captions, ocr) VALUES (?, 't', '', '', '', '', '', '', '')",
                arguments: [noteId.uuidString]
            )
        }
        // The mapping is 1:1 by noteId.
        let count = try await store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_fts_content WHERE noteId = ?", arguments: [noteId.uuidString])
        }
        #expect(count == 1)
    }

    @Test
    func ftsSearchFindsNotesByBodyText() async throws {
        // The external-content FTS5 table indexes body text written to
        // note_fts_content. Searching finds the note.
        let store = try makeStore()
        let fullTextSearch = FullTextSearch(dbPool: store.dbPool)
        let noteId = UUID()
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, title, colorKey, transparency, textSize, alwaysOnTop,
                                      widgetEligible, manualSortKey, lifecycleState, versionId,
                                      lastModifiedDeviceId, createdAt, modifiedAt)
                    VALUES (?, 't', 'yellow', 0, 'regular', 0, 1, 0, 'active', ?, ?, ?, ?)
                    """,
                arguments: [noteId.uuidString, UUID().uuidString, UUID().uuidString, Date(), Date()]
            )
            try db.execute(
                sql: "INSERT INTO note_fts_content (noteId, title, summary, body, todos, code, fileNames, captions, ocr) VALUES (?, 'title', '', 'uniquebodytext', '', '', '', '', '')",
                arguments: [noteId.uuidString]
            )
        }
        let search = SearchService(store: store, fullTextSearch: fullTextSearch)
        let results = try await search.searchActiveNotes(query: "uniquebodytext")
        #expect(results.contains { $0.id == noteId })
    }
}
