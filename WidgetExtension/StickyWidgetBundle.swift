import WidgetKit
import SwiftUI
import Domain
import Persistence
import GRDB

// MARK: - StickyWidgetBundle (T169, US8)
//
// Per tasks.md T169 and spec FR-110/FR-111/FR-112: WidgetKit + SwiftUI
// families per spec — small-selected, small-recent, medium-multi,
// medium-todo, large-overview, quick-create action. Privacy-safe: never
// expose widget-ineligible notes (FR-112); the no-eligible-note fallback
// renders the sanitized FR-140a "temporarily unavailable" placeholder.

@main
public struct StickyWidgetBundle: WidgetBundle {
    public init() {}

    public var body: some Widget {
        SmallSelectedWidget()
        SmallRecentWidget()
        MediumMultiWidget()
        MediumTodoWidget()
        LargeOverviewWidget()
        QuickCreateWidget()
    }
}

// MARK: - Shared data access (short transactions, privacy-safe)

/// Reads widget-eligible notes from the App Group SQLite in SHORT
/// transactions (FR-140a bounded busy timeout; schema-mismatch fallback
/// without crash).
public enum WidgetDataReader {
    /// The App Group container database path.
    public static func databasePath() -> String? {
        guard let container = AppGroupContainer.url(for: "group.local.stickynotes.placeholder") else {
            return nil
        }
        return container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("stickynotes.sqlite", isDirectory: false).path
    }

    /// Fetches up to `limit` widget-eligible active notes (title/summary
    /// + modifiedAt + id only — never full content beyond the card
    /// projection). Returns nil when the database is unavailable (privacy-
    /// safe fallback). SYNCHRONOUS: a short read transaction, well within
    /// the FR-140a bounded busy timeout.
    public static func fetchEligibleNotes(limit: Int) -> [NoteCardProjection]? {
        guard let path = databasePath() else { return nil }
        guard let pool = try? WidgetDatabase.openPool(path: path) else { return nil }
        defer { try? pool.close() }
        do {
            let rows = try pool.read { db in
                try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM note WHERE lifecycleState = 'active' ORDER BY modifiedAt DESC LIMIT ?",
                    arguments: [limit]
                )
            }
            return rows.compactMap { row -> NoteCardProjection? in
                guard let noteId = UUID(uuidString: row["id"] ?? "") else { return nil }
                return NoteCardProjection(
                    noteId: noteId,
                    title: row["title"],
                    generatedSummary: nil,
                    previewSource: nil,
                    colorKey: NoteColorKey(rawValue: row["colorKey"] ?? "") ?? .yellow,
                    modifiedAt: row["modifiedAt"] ?? Date(),
                    todoCompleted: 0,
                    todoTotal: 0,
                    hasScreenshot: false,
                    hasImage: false,
                    hasFileReference: false,
                    isConflictCopy: false,
                    syncWarning: false,
                    widgetEligible: row["widgetEligible"] ?? true
                )
            }
            .filter { $0.widgetEligible }
        } catch {
            return nil
        }
    }

    /// The todo items for a note (medium-todo widget). Synchronous, short
    /// transaction.
    public static func fetchTodos(noteId: UUID, limit: Int) -> [TodoItem]? {
        guard let path = databasePath() else { return nil }
        guard let pool = try? WidgetDatabase.openPool(path: path) else { return nil }
        defer { try? pool.close() }
        do {
            let rows = try pool.read { db in
                try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM todoItem WHERE noteId = ? ORDER BY sortKey ASC LIMIT ?",
                    arguments: [noteId.uuidString, limit]
                )
            }
            return rows.compactMap { row in
                TodoItem(
                    id: UUID(uuidString: row["id"] ?? "") ?? UUID(),
                    noteId: noteId,
                    blockId: UUID(uuidString: row["blockId"] ?? "") ?? UUID(),
                    parentTodoId: (row["parentTodoId"] as String?).flatMap { UUID(uuidString: $0) },
                    sortKey: row["sortKey"] ?? 0,
                    depth: row["depth"] ?? 0,
                    isComplete: row["isComplete"] ?? false,
                    lastModifiedDeviceId: UUID(uuidString: row["lastModifiedDeviceId"] ?? "") ?? UUID()
                )
            }
        } catch {
            return nil
        }
    }
}

// MARK: - Families

/// Small: one user-selected note (FR-111). The selection is stored in the
/// shared App Group store by the app's `WidgetNoteSelection` action (T306)
/// — the small-selected and medium-todo forms read it at timeline
/// generation. (The beta toolchain ICEs on AppIntentConfiguration with a
/// custom AppEntity; the intent surface is preserved for actions.)
public struct SmallSelectedWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickyWidgetSmallSelected", provider: SelectedNoteProvider()) { entry in
            SmallSelectedView(noteId: entry.selectedNoteId)
        }
        .configurationDisplayName("Selected Note")
    }
}

public struct SelectedNoteEntry: TimelineEntry {
    public let date: Date
    public let selectedNoteId: UUID?
    public init(date: Date, selectedNoteId: UUID?) {
        self.date = date
        self.selectedNoteId = selectedNoteId
    }
}

public struct SelectedNoteProvider: TimelineProvider {
    public init() {}
    public func placeholder(in context: Context) -> SelectedNoteEntry {
        SelectedNoteEntry(date: Date(), selectedNoteId: nil)
    }
    public func getSnapshot(in context: Context, completion: @escaping (SelectedNoteEntry) -> Void) {
        completion(SelectedNoteEntry(date: Date(), selectedNoteId: WidgetSelectionStore.read()))
    }
    public func getTimeline(in context: Context, completion: @escaping (Timeline<SelectedNoteEntry>) -> Void) {
        completion(Timeline(
            entries: [SelectedNoteEntry(date: Date(), selectedNoteId: WidgetSelectionStore.read())],
            policy: .after(Date().addingTimeInterval(15 * 60))
        ))
    }
}

/// Small: the most recently modified note.
public struct SmallRecentWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickyWidgetSmallRecent", provider: RecentNoteProvider()) { entry in
            SmallRecentView(entry: entry)
        }
        .configurationDisplayName("Recent Note")
    }
}

/// Medium: several notes.
public struct MediumMultiWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickyWidgetMediumMulti", provider: MultiNoteProvider()) { entry in
            MultiNoteView(entries: entry.notes)
        }
        .configurationDisplayName("Notes Overview")
    }
}

/// Medium: a note's todo list (toggle from the widget — FR-110). The
/// configured note id is read from the device-local store.
public struct MediumTodoWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickyWidgetMediumTodo", provider: SelectedNoteProvider()) { entry in
            MediumTodoView(noteId: entry.selectedNoteId)
        }
        .configurationDisplayName("Todo List")
    }
}

/// Large: overview of notes + todos.
public struct LargeOverviewWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickyWidgetLargeOverview", provider: MultiNoteProvider()) { entry in
            LargeOverviewView(entries: entry.notes)
        }
        .configurationDisplayName("Overview")
    }
}

/// Quick-create action widget (FR-110).
public struct QuickCreateWidget: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickyWidgetQuickCreate", provider: QuickCreateProvider()) { _ in
            QuickCreateView()
        }
        .configurationDisplayName("Quick Create")
    }
}
