import Foundation
import GRDB
import Domain

// MARK: - FullTextSearch (T020)
//
// Per data-model.md §SearchDocument (FTS5) and plan §Search.
//
// One searchable row per note. Rebuilt transactionally on note change.
// Active notes by default; separate Trash scope query. Results never reveal
// privacy-excluded notes. Performance tests at 10,000 notes (SC-005: ≤200ms).
//
// The FTS5 table `notes_fts` is created in m0001_initial.swift as an
// external-content table synchronized with `note_fts_content`. This file
// provides the query/search API on top of that index.

/// The full-text search service. Reads/writes the `note_fts_content` table
/// (which the FTS5 triggers keep in sync with `notes_fts`).
public struct FullTextSearch: Sendable {
    public let dbPool: DatabasePool

    public init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    // MARK: - Search

    /// Searches active notes (default scope) for the given query. Returns
    /// matching note ids ranked by FTS5 relevance.
    ///
    /// Trashed/permanentlyDeleted/conflictCopy notes are excluded by default;
    /// the Trash scope is a separate query.
    public func searchActiveNotes(query: String, limit: Int = 100) async throws -> [SearchResult] {
        try await search(
            query: query,
            lifecycleFilter: "note.lifecycleState = 'active'",
            limit: limit
        )
    }

    /// Searches trashed notes (Trash scope).
    public func searchTrashedNotes(query: String, limit: Int = 100) async throws -> [SearchResult] {
        try await search(
            query: query,
            lifecycleFilter: "note.lifecycleState = 'trashed'",
            limit: limit
        )
    }

    /// Common search implementation. Joins `notes_fts` against `note` for
    /// lifecycle filtering, and ranks by FTS5 relevance.
    private func search(query: String, lifecycleFilter: String, limit: Int) async throws -> [SearchResult] {
        // Empty query → no FTS results (the SearchService caller falls back
        // to a plain `SELECT` for "show all" before the user types).
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // R3.5 (remediation roadmap 2026-08-14): GRDB's FTS5Pattern owns
        // the quoting/prefix construction (all-tokens AND semantics with
        // `*` type-ahead prefixes) — the hand-built MATCH pattern above
        // re-implemented it without NEAR/phrase/tokenizer edge handling.
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: trimmed) else {
            return []
        }

        return try await dbPool.read { db in
            // Build SQL with string concatenation to avoid GRDB's SQL
            // literal interpolation (lifecycleFilter is raw SQL, not a
            // bindable value).
            //
            // JOIN path: notes_fts (FTS5 external content table) →
            // note_fts_content (the content table, provides noteId) →
            // note (for lifecycle filtering + display cols).
            let sql = """
                SELECT note.id, note.title, note.modifiedAt, notes_fts.rank
                FROM notes_fts
                JOIN note_fts_content ON note_fts_content.rowid = notes_fts.rowid
                JOIN note ON note.id = note_fts_content.noteId
                WHERE notes_fts MATCH ?
                  AND \(lifecycleFilter)
                ORDER BY notes_fts.rank
                LIMIT ?
                """ as String
            let args: [any DatabaseValueConvertible] = [pattern, limit]
            let request = SQLRequest<Row>(sql: sql, arguments: StatementArguments(args))
            let rows = try Row.fetchAll(db, request)
            return rows.map { row in
                SearchResult(
                    id: UUID(uuidString: row["id"] ?? "") ?? UUID(),
                    title: row["title"],
                    modifiedAt: row["modifiedAt"] ?? Date(),
                    rank: (row["rank"] as Double?) ?? 0
                )
            }
        }
    }

    // MARK: - Index maintenance
    //
    // The SearchService (T042) writes a `SearchDocument` to
    // `note_fts_content` transactionally whenever a note changes. The FTS5
    // triggers (created in m0001) keep `notes_fts` in sync automatically.

    /// Replaces the search document for the given note. Called within a
    /// write transaction by NoteRepository when a note changes (T030 / T042).
    public func upsertSearchDocument(_ doc: SearchDocument) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note_fts_content (noteId, title, summary, body, todos, code, fileNames, captions, ocr)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(noteId) DO UPDATE SET
                        title = excluded.title,
                        summary = excluded.summary,
                        body = excluded.body,
                        todos = excluded.todos,
                        code = excluded.code,
                        fileNames = excluded.fileNames,
                        captions = excluded.captions,
                        ocr = excluded.ocr
                    """,
                arguments: [
                    doc.noteId.uuidString,
                    doc.title,
                    doc.summary,
                    doc.body,
                    doc.todos,
                    doc.code,
                    doc.fileNames,
                    doc.captions,
                    doc.ocr,
                ]
            )
        }
    }

    /// Removes the search document for the given note (e.g., on permanent
    /// delete). Called within a write transaction by NoteRepository.
    public func deleteSearchDocument(noteId: UUID) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM note_fts_content WHERE noteId = ?",
                arguments: [noteId.uuidString]
            )
        }
    }
}

// MARK: - SearchResult
//
// A Sendable snapshot of a search hit. Concrete DB rows are NOT exported
// as contracts (plan §Module boundaries).

public struct SearchResult: Sendable, Identifiable, Equatable {
    public let id: UUID             // note id
    public let title: String?
    public let modifiedAt: Date
    public let rank: Double

    public init(id: UUID, title: String?, modifiedAt: Date, rank: Double) {
        self.id = id
        self.title = title
        self.modifiedAt = modifiedAt
        self.rank = rank
    }
}
