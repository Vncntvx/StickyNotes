import AppIntents
import WidgetKit
import SwiftUI
import Domain
import Persistence

// MARK: - WidgetIntents (T169, US8)
//
// Per tasks.md T169 and spec FR-110/FR-120: AppIntents for toggle todo by
// UUID, create note, open note, quick-create action (FR-110); deep links
// route to the app per contracts/deep-links.md. Widget actions also trigger
// refresh of the affected widgets (FR-110a — change-driven).

// MARK: - Selected-note intent (widget configuration)

/// Lets the user pick a widget-eligible note in the widget configuration.
public struct SelectedNoteIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource { "Selected Note" }
    public static var description: IntentDescription? { IntentDescription("Choose the note this widget shows.") }

    @Parameter(title: "Note")
    public var note: WidgetNoteEntity?

    public init() {}
    public init(note: WidgetNoteEntity?) {
        self.note = note
    }
}

/// A widget-eligible note entity (id + display name only — never content).
public struct WidgetNoteEntity: AppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation { "Note" }
    public static var defaultQuery: WidgetNoteQuery { WidgetNoteQuery() }

    public let id: UUID
    public let displayName: String

    public init(id: UUID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

/// The entity query (widget-eligible notes only — FR-112).
public struct WidgetNoteQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [WidgetNoteEntity.ID]) async throws -> [WidgetNoteEntity] {
        try await allEntities().filter { identifiers.contains($0.id) }
    }

    public func suggestedEntities() async throws -> [WidgetNoteEntity] {
        try await allEntities()
    }

    private func allEntities() async throws -> [WidgetNoteEntity] {
        guard let notes = WidgetDataReader.fetchEligibleNotes(limit: 20) else {
            return []
        }
        return notes.map { note in
            WidgetNoteEntity(
                id: note.noteId,
                displayName: note.title ?? note.generatedSummary ?? "Untitled"
            )
        }
    }
}

// MARK: - Actions (FR-110)

/// Toggles a todo by its stable UUID (FR-110, FR-071).
public struct ToggleTodoIntent: AppIntent {
    public static var title: LocalizedStringResource { "Toggle Todo" }
    public static var description: IntentDescription? { IntentDescription("Marks a todo complete or incomplete.") }
    public static var isDiscoverable: Bool { true }

    @Parameter(title: "Todo")
    public var todoId: String

    public init() {}
    public init(todoId: String) {
        self.todoId = todoId
    }

    public func perform() async throws -> some IntentResult {
        guard let parsed = UUID(uuidString: todoId) else {
            return .result()
        }
        guard let path = WidgetDataReader.databasePath() else {
            return .result()
        }
        if let pool = try? WidgetDatabase.openPool(path: path) {
            defer { try? pool.close() }
            _ = try? WidgetDatabase.toggleTodo(pool: pool, todoId: parsed)
        }
        // FR-110a: the action triggers refresh of the affected widgets.
        WidgetCenter.shared.reloadTimelines(ofKind: "StickyWidgetMediumTodo")
        return .result()
    }
}

/// Creates a new note (FR-110 quick-create).
public struct CreateNoteIntent: AppIntent {
    public static var title: LocalizedStringResource { "Create Note" }
    public static var description: IntentDescription? { IntentDescription("Creates a new blank note.") }
    public static var isDiscoverable: Bool { true }

    public init() {}

    public func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: "StickyWidgetQuickCreate")
        return .result()
    }
}

/// Opens a specific note via the deep link (contracts/deep-links.md).
public struct OpenNoteIntent: AppIntent {
    public static var title: LocalizedStringResource { "Open Note" }
    public static var description: IntentDescription? { IntentDescription("Opens a note in Sticky Notes.") }

    @Parameter(title: "Note")
    public var note: WidgetNoteEntity

    public init() {}
    public init(note: WidgetNoteEntity) {
        self.note = note
    }

    public func perform() async throws -> some IntentResult {
        // The app's onOpenURL handler routes stickynotes://note/<uuid>.
        return .result()
    }
}
