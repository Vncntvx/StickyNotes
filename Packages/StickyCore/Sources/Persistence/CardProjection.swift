import Foundation
import GRDB
import Domain

// MARK: - CardProjection (T134/T172)
//
// Per tasks.md T134 and plan §Accessibility/§Performance: "lazy card-grid
// projections + bounded result loading". The menu-bar library renders cards
// from a projection that carries exactly what a card needs — display title,
// 2-line preview source, color, last-modified, todo progress (FR-072b
// "completed/total" / "99+ completed"), and presence indicators — WITHOUT
// loading full block payloads or assets.
//
// The projection is computed with bounded loads:
// - `fetchCardProjections` runs one SQL query per sort order (no N+1).
// - Todo progress is aggregated in SQL (counts only — no todo rows).
// - Indicator presence (screenshot / image / file-ref) is a tiny per-note
//   EXISTS query aggregated into a single GROUP BY.
//
// FR-072b (clarified 2026-08-07): the card progress string is
// "completed/total" (e.g. "12/45"); totals > 99 render as "99+ completed".
// FR-020a: the body preview draws from the first rich-text block, never
// duplicating the generated summary title — `previewSource` carries the
// first rich-text block's text; the App view truncates it at 2 rendered
// lines with a trailing ellipsis.

/// A compact, ready-to-render card row. `Sendable` snapshot (plan §Module
/// boundaries — concrete GRDB rows are never exported).
public struct NoteCardProjection: Sendable, Identifiable, Equatable {
    public let noteId: UUID
    public let title: String?                // manual title
    public let generatedSummary: String?     // FR-045 display-only summary
    public let previewSource: String?        // first rich-text block text (FR-020a)
    public let colorKey: NoteColorKey
    /// The raw custom-color hex (`.custom` keys only; nil for built-ins).
    /// Card surfaces render custom colors from this value — the Domain
    /// `builtinRGB` path is nil for `.custom` (verified 2026-08-09: a
    /// peach note — stored as `.custom + #FFC9A8` per FR-032 — rendered
    /// WHITE in the library grid).
    public let customColorHex: String?
    public let modifiedAt: Date
    public let todoCompleted: Int
    public let todoTotal: Int
    public let hasScreenshot: Bool
    public let hasImage: Bool
    public let hasFileReference: Bool
    public let isConflictCopy: Bool
    /// The conflict-copy label (FR-175) — nil for non-conflict notes.
    public let conflictLabel: String?
    public let syncWarning: Bool             // partialAssetSyncFailure on any asset

    public var id: UUID { noteId }

    public init(
        noteId: UUID,
        title: String?,
        generatedSummary: String?,
        previewSource: String?,
        colorKey: NoteColorKey,
        customColorHex: String?,
        modifiedAt: Date,
        todoCompleted: Int,
        todoTotal: Int,
        hasScreenshot: Bool,
        hasImage: Bool,
        hasFileReference: Bool,
        isConflictCopy: Bool,
        conflictLabel: String? = nil,
        syncWarning: Bool
    ) {
        self.noteId = noteId
        self.title = title
        self.generatedSummary = generatedSummary
        self.previewSource = previewSource
        self.colorKey = colorKey
        self.customColorHex = customColorHex
        self.modifiedAt = modifiedAt
        self.todoCompleted = todoCompleted
        self.todoTotal = todoTotal
        self.hasScreenshot = hasScreenshot
        self.hasImage = hasImage
        self.hasFileReference = hasFileReference
        self.isConflictCopy = isConflictCopy
        self.conflictLabel = conflictLabel
        self.syncWarning = syncWarning
    }

    /// Todo progress per FR-072b: "completed/total", or "99+ completed"
    /// when the total exceeds 99 (card width safety). Language-neutral
    /// formatting helper; the App layer localizes surrounding text.
    public var todoProgressString: String? {
        TodoCardProgress.format(completed: todoCompleted, total: todoTotal)
    }
}

/// Fetches bounded card projections from the database.
public enum CardProjection {
    /// The maximum number of card rows fetched per query (bounded result
    /// loading; plan §Performance).
    public static let maxRows = 500

    /// SQL fragment restricting the query to the given note ids (FTS search
    /// results, T283). Returns an empty string when nil.
    public static func noteIdFilter(_ noteIds: Set<UUID>?) -> String {
        guard let noteIds, !noteIds.isEmpty else { return "" }
        let list = noteIds.map { "'\($0.uuidString)'" }.joined(separator: ",")
        return "AND n.id IN (\(list))"
    }

    /// Fetch card projections for the given lifecycle state and sort order.
    /// Bounded to `maxRows`; cheapest per-note aggregation queries only.
    /// When `noteIds` is non-nil (e.g. FTS search results, T283), only those
    /// notes are fetched and the row bound does not apply — a search result
    /// beyond the first 500 cards must still appear (FR-023/SC-005).
    public static func fetchCardProjections(
        store: DatabaseStore,
        lifecycle: NoteLifecycleState,
        sort: NoteSortKey,
        limit: Int = maxRows,
        noteIds: Set<UUID>? = nil
    ) async throws -> [NoteCardProjection] {
        try await fetchCardProjections(
            store: store,
            lifecycleStates: [lifecycle],
            sort: sort,
            limit: limit,
            noteIds: noteIds
        )
    }

    /// R2.1 (Phase 2): fetches cards for MULTIPLE lifecycle states in one
    /// query (e.g. the library's [.active, .conflictCopy] — FR-175). The
    /// single-lifecycle overload delegates here.
    public static func fetchCardProjections(
        store: DatabaseStore,
        lifecycleStates: Set<NoteLifecycleState>,
        sort: NoteSortKey,
        limit: Int = maxRows,
        noteIds: Set<UUID>? = nil
    ) async throws -> [NoteCardProjection] {
        try await store.read { db in
            let orderClause: String
            switch sort {
            case .modified: orderClause = "n.modifiedAt DESC"
            case .created:  orderClause = "n.createdAt DESC"
            case .title:    orderClause = "n.title IS NULL, n.title ASC"
            case .manual:   orderClause = "n.manualSortKey ASC"
            }

            // Todo aggregates per note (counts only — never todo rows).
            let todoAgg: [UUID: (completed: Int, total: Int)] = try {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT noteId,
                               SUM(CASE WHEN isComplete THEN 1 ELSE 0 END) AS completed,
                               COUNT(*) AS total
                        FROM todoItem
                        GROUP BY noteId
                        """
                )
                var map: [UUID: (Int, Int)] = [:]
                for row in rows {
                    guard let noteId = UUID(uuidString: row["noteId"] ?? "") else { continue }
                    map[noteId] = (row["completed"] ?? 0, row["total"] ?? 0)
                }
                return map
            }()

            // Indicator aggregates per note (existence only).
            let indicators: [UUID: (screenshot: Bool, image: Bool, fileRef: Bool)] = try {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT noteId,
                               SUM(CASE WHEN kind = 'screenshot' THEN 1 ELSE 0 END) > 0 AS hasShot,
                               SUM(CASE WHEN kind = 'image' THEN 1 ELSE 0 END) > 0 AS hasImage,
                               SUM(CASE WHEN kind = 'fileRef' THEN 1 ELSE 0 END) > 0 AS hasFile
                        FROM block
                        GROUP BY noteId
                        """
                )
                var map: [UUID: (Bool, Bool, Bool)] = [:]
                for row in rows {
                    guard let noteId = UUID(uuidString: row["noteId"] ?? "") else { continue }
                    map[noteId] = (row["hasShot"] ?? false, row["hasImage"] ?? false, row["hasFile"] ?? false)
                }
                return map
            }()

            // Sync warnings: any asset in partial-failure state.
            let syncWarnings: Set<UUID> = try {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT s.noteId
                        FROM asset a
                        JOIN screenshotAssociation s ON s.originalAssetId = a.id OR s.thumbnailAssetId = a.id
                        WHERE a.syncFailureState != 'none'
                        """
                )
                return Set(rows.compactMap { UUID(uuidString: $0["noteId"] ?? "") })
            }()

            // First rich-text block text per note (preview source, FR-020a):
            // the first richText block by sortKey — never the summary title.
            let previews: [UUID: String] = try {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT noteId, payload
                        FROM block
                        WHERE kind = 'richText'
                        ORDER BY noteId, sortKey ASC
                        """
                )
                let decoder = CanonicalJSONDecoder()
                var map: [UUID: String] = [:]
                for row in rows {
                    let noteId = UUID(uuidString: row["noteId"] ?? "") ?? UUID()
                    guard map[noteId] == nil else { continue }  // first only
                    guard let payloadString: String = row["payload"],
                          let data = payloadString.data(using: .utf8),
                          let payload = try? decoder.decode(CanonicalBlockPayload.self, from: data),
                          case .richText(let doc) = payload else { continue }
                    let text = doc.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { map[noteId] = text }
                }
                return map
            }()

            let placeholders = Array(repeating: "?", count: lifecycleStates.count).joined(separator: ",")
            let stateArgs: [any DatabaseValueConvertible] = lifecycleStates.map(\.rawValue)
            let finalArgs: [any DatabaseValueConvertible] = noteIds == nil ? stateArgs + [limit] : stateArgs
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT n.*
                    FROM note n
                    WHERE n.lifecycleState IN (\(placeholders))
                    \(Self.noteIdFilter(noteIds))
                    \(noteIds == nil ? "ORDER BY \(orderClause) LIMIT ?" : "ORDER BY \(orderClause)")
                    """,
                arguments: StatementArguments(finalArgs)
            )

            return rows.compactMap { row -> NoteCardProjection? in
                guard let noteId = UUID(uuidString: row["id"] ?? "") else { return nil }
                // Generated summary derives from the first meaningful block —
                // which is the preview source for rich-text notes (FR-045,
                // FR-020a). Deterministic, no disambiguation (FR-021).
                let summary: String?
                if let preview = previews[noteId] {
                    summary = NoteSummary.generatedSummary(for: [
                        Block(
                            noteId: noteId,
                            kind: .richText,
                            sortKey: 0,
                            payload: .richText(.plain(preview)),
                            lastModifiedDeviceId: UUID()
                        )
                    ])
                } else {
                    summary = nil
                }
                let todo = todoAgg[noteId] ?? (0, 0)
                let ind = indicators[noteId] ?? (false, false, false)
                return NoteCardProjection(
                    noteId: noteId,
                    title: row["title"],
                    generatedSummary: summary,
                    previewSource: previews[noteId],
                    colorKey: NoteColorKey(rawValue: row["colorKey"] ?? "") ?? .yellow,
                    customColorHex: row["customColor"],
                    modifiedAt: row["modifiedAt"] ?? Date(),
                    todoCompleted: todo.0,
                    todoTotal: todo.1,
                    hasScreenshot: ind.0,
                    hasImage: ind.1,
                    hasFileReference: ind.2,
                    isConflictCopy: (row["lifecycleState"] ?? "") == NoteLifecycleState.conflictCopy.rawValue,
                    conflictLabel: row["conflictLabel"],
                    syncWarning: syncWarnings.contains(noteId)
                )
            }
        }
    }
}
