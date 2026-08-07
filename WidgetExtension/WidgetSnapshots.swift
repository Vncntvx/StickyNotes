import WidgetKit
import SwiftUI
import Domain
import Persistence

// MARK: - WidgetSnapshots (T169/T101/T280)
//
// Per tasks.md T169/T101/T280 and spec FR-140a/FR-112: privacy-safe
// placeholders/snapshots + graceful handling of deleted/trashed/conflicted/
// unavailable configured notes. When NO eligible note exists (every note
// excluded, or the configured note deleted/trashed/conflicted), every
// widget form shows the sanitized FR-140a "temporarily unavailable"
// placeholder — localized, no content, no note title, never implying an
// excluded note exists (FR-112).

// MARK: - Providers

public struct RecentNoteEntry: TimelineEntry {
    public let date: Date
    public let note: NoteCardProjection?
    public init(date: Date, note: NoteCardProjection?) {
        self.date = date
        self.note = note
    }
}

public struct MultiNoteEntry: TimelineEntry {
    public let date: Date
    public let notes: [NoteCardProjection]
    public init(date: Date, notes: [NoteCardProjection]) {
        self.date = date
        self.notes = notes
    }
}

public struct RecentNoteProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> RecentNoteEntry {
        RecentNoteEntry(date: Date(), note: nil)
    }

    public func getSnapshot(in context: Context, completion: @escaping (RecentNoteEntry) -> Void) {
        completion(RecentNoteEntry(date: Date(), note: WidgetDataReader.fetchEligibleNotes(limit: 1)?.first))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<RecentNoteEntry>) -> Void) {
        let note = WidgetDataReader.fetchEligibleNotes(limit: 1)?.first
        // Change-driven refresh (FR-110a): a short "refresh soon" policy
        // with NO high-frequency polling (SC-006).
        let entry = RecentNoteEntry(date: Date(), note: note)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

public struct MultiNoteProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> MultiNoteEntry {
        MultiNoteEntry(date: Date(), notes: [])
    }

    public func getSnapshot(in context: Context, completion: @escaping (MultiNoteEntry) -> Void) {
        completion(MultiNoteEntry(date: Date(), notes: WidgetDataReader.fetchEligibleNotes(limit: 5) ?? []))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<MultiNoteEntry>) -> Void) {
        let notes = WidgetDataReader.fetchEligibleNotes(limit: 5) ?? []
        completion(Timeline(
            entries: [MultiNoteEntry(date: Date(), notes: notes)],
            policy: .after(Date().addingTimeInterval(15 * 60))
        ))
    }
}

public struct QuickCreateProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> MultiNoteEntry {
        MultiNoteEntry(date: Date(), notes: [])
    }

    public func getSnapshot(in context: Context, completion: @escaping (MultiNoteEntry) -> Void) {
        completion(MultiNoteEntry(date: Date(), notes: []))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<MultiNoteEntry>) -> Void) {
        completion(Timeline(entries: [MultiNoteEntry(date: Date(), notes: [])], policy: .never))
    }
}

// MARK: - Views

/// Widget-local relative-time helper (the widget target cannot import the
/// App layer's DisplayFormatters).
private enum WidgetFormatters {
    static func lastModified(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) hr ago" }
        return "\(Int(seconds / 86_400)) days ago"
    }
}

/// The FR-140a sanitized "temporarily unavailable" placeholder (FR-112).
public struct TemporarilyUnavailableView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "note.text")
                .foregroundStyle(.secondary)
            Text("Temporarily unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct SmallRecentView: View {
    public let entry: RecentNoteEntry

    public init(entry: RecentNoteEntry) {
        self.entry = entry
    }

    public var body: some View {
        Group {
            if let note = entry.note {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title ?? note.generatedSummary ?? "Untitled")
                        .font(.headline)
                        .lineLimit(2)
                    if let preview = note.previewSource {
                        Text(preview)
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(WidgetFormatters.lastModified(note.modifiedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                // FR-112/FR-140a: no eligible note → sanitized placeholder,
                // no title, never implying an excluded note exists.
                TemporarilyUnavailableView()
            }
        }
        .padding(12)
    }
}

public struct SmallSelectedView: View {
    public let noteId: UUID?

    public init(noteId: UUID?) {
        self.noteId = noteId
    }

    public var body: some View {
        Group {
            if let noteId {
                // The configured note may be deleted/trashed/conflicted —
                // graceful fallback (T101). The view resolves the note in a
                // background task.
                ResolvedNoteView(noteId: noteId)
            } else {
                TemporarilyUnavailableView()
            }
        }
    }
}

public struct MultiNoteView: View {
    public let entries: [NoteCardProjection]

    public init(entries: [NoteCardProjection]) {
        self.entries = entries
    }

    public var body: some View {
        Group {
            if entries.isEmpty {
                TemporarilyUnavailableView()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entries.prefix(3), id: \.noteId) { note in
                        HStack {
                            Circle()
                                .fill(noteColor(note.colorKey))
                                .frame(width: 8, height: 8)
                            Text(note.title ?? note.generatedSummary ?? "Untitled")
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(WidgetFormatters.lastModified(note.modifiedAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private func noteColor(_ key: NoteColorKey) -> Color {
        guard let rgb = key.builtinRGB else { return .gray }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

public struct MediumTodoView: View {
    public let noteId: UUID?

    public init(noteId: UUID?) {
        self.noteId = noteId
    }

    public var body: some View {
        Group {
            if let noteId {
                ResolvedTodosView(noteId: noteId)
            } else {
                TemporarilyUnavailableView()
            }
        }
        .padding(12)
    }
}

/// Resolves a selected note asynchronously (T101 graceful fallback).
private struct ResolvedNoteView: View {
    let noteId: UUID
    @State private var note: NoteCardProjection?

    var body: some View {
        Group {
            if let note {
                SmallRecentView(entry: RecentNoteEntry(date: Date(), note: note))
            } else {
                TemporarilyUnavailableView()
            }
        }
        .task {
            note = WidgetDataReader.fetchEligibleNotes(limit: 20)?.first(where: { $0.noteId == noteId })
        }
    }
}

/// Resolves a note's todos asynchronously.
private struct ResolvedTodosView: View {
    let noteId: UUID
    @State private var todos: [TodoItem] = []

    var body: some View {
        Group {
            if todos.isEmpty {
                TemporarilyUnavailableView()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(todos, id: \.id) { todo in
                        Button(intent: ToggleTodoIntent(todoId: todo.id.uuidString)) {
                            HStack(spacing: 6) {
                                Image(systemName: todo.isComplete ? "checkmark.square.fill" : "square")
                                Text("Todo")
                                    .lineLimit(1)
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task {
            todos = WidgetDataReader.fetchTodos(noteId: noteId, limit: 4) ?? []
        }
    }
}

public struct LargeOverviewView: View {
    public let entries: [NoteCardProjection]

    public init(entries: [NoteCardProjection]) {
        self.entries = entries
    }

    public var body: some View {
        Group {
            if entries.isEmpty {
                TemporarilyUnavailableView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.headline)
                    ForEach(entries.prefix(5), id: \.noteId) { note in
                        HStack {
                            Text(note.title ?? note.generatedSummary ?? "Untitled")
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            if let progress = note.todoProgressString {
                                Text(progress)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
    }
}

public struct QuickCreateView: View {
    public init() {}

    public var body: some View {
        Button(intent: CreateNoteIntent()) {
            VStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                Text("New Note")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}
