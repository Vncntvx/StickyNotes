import Foundation
import GRDB
import Domain

// MARK: - SearchService (T042)
//
// Per tasks.md T042 and plan §Search / data-model.md §SearchDocument (FTS5):
//
// - One searchable document per note: manual title, generated summary
//   source, normal text, todo text, code text, file display names,
//   screenshot captions, future OCR text.
// - Indexed transactionally with note changes.
// - Active notes by default; results never reveal non-active notes.
// - Performance tests at 10,000 notes (SC-005: ≤200 ms).
//
// The FTS5 virtual table `notes_fts` and its content table `note_fts_content`
// are created in m0001_initial.swift. This service:
//   1. Builds a `SearchDocument` projection from a note + its blocks.
//   2. Writes the projection to `note_fts_content` transactionally.
//   3. Delegates MATCH queries to `FullTextSearch` (T020).

/// Builds and queries the per-note search document. `Sendable` — wraps the
/// GRDB `DatabasePool` (which is `Sendable`).
public final class SearchService: Sendable {
    private let store: DatabaseStore
    private let fullTextSearch: FullTextSearch

    public init(store: DatabaseStore, fullTextSearch: FullTextSearch) {
        self.store = store
        self.fullTextSearch = fullTextSearch
    }

    // MARK: - Query

    /// Searches active notes for the given query. Returns matching note ids
    /// ranked by FTS5 relevance.
    public func searchActiveNotes(query: String, limit: Int = 100) async throws -> [SearchResult] {
        try await fullTextSearch.searchActiveNotes(query: query, limit: limit)
    }

    /// Searches trashed notes (Trash scope).
    public func searchTrashedNotes(query: String, limit: Int = 100) async throws -> [SearchResult] {
        try await fullTextSearch.searchTrashedNotes(query: query, limit: limit)
    }

    // MARK: - Index maintenance

    /// Rebuilds the search document for a note from its blocks. Called by
    /// the editor / repository whenever a note or its blocks change, within
    /// the same write transaction so the FTS5 trigger fires atomically.
    public func reindexNote(noteId: UUID, title: String?, blocks: [Block]) async throws {
        let doc = buildSearchDocument(noteId: noteId, title: title, blocks: blocks)
        try await fullTextSearch.upsertSearchDocument(doc)
    }

    /// Removes the search document for a note (e.g., on permanent delete).
    public func removeNote(noteId: UUID) async throws {
        try await fullTextSearch.deleteSearchDocument(noteId: noteId)
    }

    /// Rebuilds the search index for every note in the database. Used after
    /// a migration that changes block payload encoding, or as a maintenance
    /// operation. Safe to run while the app is live (each note is its own
    /// small transaction).
    public func rebuildAllIndices(blocksFetcher: @escaping @Sendable (UUID) async throws -> [Block]) async throws {
        let noteIds: [(UUID, String?)] = try await store.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, title FROM note")
            return rows.map { row in
                (UUID(uuidString: row["id"] ?? "") ?? UUID(), row["title"])
            }
        }
        for (noteId, title) in noteIds {
            let blocks = try await blocksFetcher(noteId)
            try await reindexNote(noteId: noteId, title: title, blocks: blocks)
        }
    }

    // MARK: - SearchDocument projection

    /// Builds a `SearchDocument` from a note + its blocks. Pure function —
    /// no DB access — so it's trivially testable.
    public func buildSearchDocument(noteId: UUID, title: String?, blocks: [Block]) -> SearchDocument {
        var body: [String] = []
        var todos: [String] = []
        var code: [String] = []
        var fileNames: [String] = []
        var captions: [String] = []

        for block in blocks {
            switch block.payload {
            case .richText(let doc):
                body.append(doc.text)
            case .todo(let payload):
                todos.append(payload.richText.text)
            case .code(let payload):
                code.append(payload.text)
            case .fileReference(let payload):
                fileNames.append(payload.displayName)
                if let caption = payload.caption, !caption.isEmpty {
                    captions.append(caption)
                }
            case .image(let payload):
                if let caption = payload.caption, !caption.isEmpty {
                    captions.append(caption)
                }
            case .screenshot(let payload):
                if let caption = payload.caption, !caption.isEmpty {
                    captions.append(caption)
                }
            }
        }

        // Summary source: the generated summary's underlying text (so the
        // source content is searchable even though the summary itself is a
        // display-only projection per FR-045).
        let summarySource = NoteSummary.generatedSummary(for: blocks) ?? ""

        return SearchDocument(
            noteId: noteId,
            title: title ?? "",
            summary: summarySource,
            body: body.joined(separator: " "),
            todos: todos.joined(separator: " "),
            code: code.joined(separator: " "),
            fileNames: fileNames.joined(separator: " "),
            captions: captions.joined(separator: " "),
            ocr: ""
        )
    }
}
