import Foundation
import GRDB
import Domain

// MARK: - WidgetDatabase (T094)
//
// Per tasks.md T094 and plan §Widgets / research.md R6:
//
// - Widgets read the App Group SQLite in SHORT transactions with a bounded
//   busy timeout (1s, widget-like).
// - Todo updates are SMALL ATOMIC writes (single transaction, `isComplete`
//   flip + version lineage bump).
// - Schema-mismatch fallback: the widget detects an unsupported/missing
//   schema via `StickyMigrator.currentSchemaVersion` and falls back to
//   privacy-safe placeholders WITHOUT crashing and WITHOUT migrating
//   (research.md R6 — the main app owns migrations).
// - The widget NEVER initializes the sync engine (constitution VI, XI).
//
// This is the only Persistence surface the WidgetExtension links.

// The `TodoPayload` type referenced below is re-exported by Domain.

public enum WidgetDatabase {

    /// The widget read busy timeout (FR-140a). Short enough to never block
    /// the widget timeline refresh; within the 5s production bound.
    public static let readBusyTimeout: TimeInterval = 1.0

    /// Opens a widget pool: bounded busy timeout (widgets must never hang
    /// the timeline), WAL-friendly read-mostly access.
    public static func openPool(path: String, busyTimeout: TimeInterval = WidgetDatabase.readBusyTimeout) throws -> DatabasePool {
        var config = Configuration()
        config.busyMode = .timeout(busyTimeout)
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        config.label = "local.stickynotes.widget"
        return try DatabasePool(path: path, configuration: config)
    }

    /// Whether the database at `path` has a schema the widget understands.
    /// Returns `false` for missing/unmigrated/unknown schemas — the caller
    /// then shows privacy-safe placeholders (never crashes, never migrates).
    public static func isSchemaSupported(
        path: String,
        supportedVersion: String = StickyMigrationId.v2
    ) async -> Bool {
        guard let pool = try? openPool(path: path) else { return false }
        let version = await StickyMigrator.currentSchemaVersion(pool)
        return version == supportedVersion
    }

    /// Atomically toggles a todo item's completion state. Single short
    /// write transaction; new version lineage (constitution VIII).
    ///
    /// - Returns: the new completion state; `nil` when the todo does not
    ///   exist (deleted between widget render and tap — graceful no-op).
    public static func toggleTodo(pool: DatabasePool, todoId: UUID) throws -> Bool? {
        try pool.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT id, isComplete, noteId, lastModifiedDeviceId FROM todoItem WHERE id = ?",
                arguments: [todoId.uuidString]
            ) else { return nil }

            let wasComplete = row["isComplete"] as Bool
            let newValue = !wasComplete
            try db.execute(
                sql: """
                    UPDATE todoItem
                    SET isComplete = ?, versionId = ?, parentVersionId = versionId, modifiedAt = ?
                    WHERE id = ?
                    """,
                arguments: [
                    newValue,
                    UUID().uuidString,
                    Date().timeIntervalSince1970,
                    todoId.uuidString,
                ]
            )
            return newValue
        }
    }

    /// Short read: todo items for one note (widget timeline). The todo text
    /// comes from the block's canonical `TodoPayload` (FR-071: identity is
    /// separate from text). Returns only widget-relevant fields.
    public static func fetchTodos(pool: DatabasePool, noteId: UUID) throws -> [WidgetTodoRow] {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT t.id, b.payload, t.isComplete, t.sortKey, t.depth
                    FROM todoItem t
                    JOIN block b ON b.id = t.blockId
                    WHERE t.noteId = ?
                    ORDER BY t.sortKey
                    """,
                arguments: [noteId.uuidString]
            )
            return rows.map { row in
                let payloadJSON = row["payload"] as String? ?? "{}"
                let text = Self.todoText(from: payloadJSON)
                return WidgetTodoRow(
                    id: row["id"] ?? "",
                    text: text,
                    isComplete: row["isComplete"] ?? false,
                    sortKey: row["sortKey"] ?? 0,
                    depth: row["depth"] ?? 0
                )
            }
        }
    }

    /// Extracts the todo text from a canonical `TodoPayload` JSON string.
    /// Never throws; malformed payloads yield an empty string (the widget
    /// degrades to a checkbox rather than crashing — research.md R14).
    public static func todoText(from payloadJSON: String) -> String {
        guard let data = payloadJSON.data(using: .utf8),
              let payload = try? JSONDecoder().decode(TodoPayload.self, from: data)
        else { return "" }
        return payload.richText.plainText
    }
}

/// A minimal todo projection for widget timelines. No note content beyond
/// the todo text itself — and only for widget-eligible active notes (the
/// caller gates via `WidgetVisibility`, research.md R14).
public struct WidgetTodoRow: Sendable, Equatable {
    public let id: String
    public let text: String
    public let isComplete: Bool
    public let sortKey: Int
    public let depth: Int

    public init(id: String, text: String, isComplete: Bool, sortKey: Int, depth: Int) {
        self.id = id
        self.text = text
        self.isComplete = isComplete
        self.sortKey = sortKey
        self.depth = depth
    }
}
