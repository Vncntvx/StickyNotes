import SwiftUI
import Domain
import Persistence

// MARK: - LibrarySearchView (T164)
//
// Per tasks.md T164 and spec FR-022/FR-022a/FR-023/FR-023a/FR-024/FR-024a:
// the library search field + sort switcher among Recently Modified /
// Created / Title / Manual with prompt result updates (results begin
// updating within 100 ms of a query change — the model reloads on each
// keystroke). Search with no matching results renders the unified
// empty-state (FR-014c) and is NEVER treated as an error (FR-011a).

/// The search + sort control strip.
public struct LibrarySearchView: View {
    @Bindable var model: LibraryModel

    public init(model: LibraryModel) {
        self.model = model
    }

    public var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notes", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .onChange(of: model.searchQuery) { _, newValue in
                        // FR-024a prompt updates: debounce-free immediate
                        // reload (in-memory filter, well under 100 ms).
                        model.setSearchQuery(newValue)
                    }
                if !model.searchQuery.isEmpty {
                    Button {
                        model.searchQuery = ""
                        Task { await model.reload() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            Picker("Sort", selection: Binding(
                get: { model.sort },
                set: { model.setSort($0) }
            )) {
                Text("Recently Modified").tag(NoteSortKey.modified)
                Text("Created").tag(NoteSortKey.created)
                Text("Title").tag(NoteSortKey.title)
                Text("Manual").tag(NoteSortKey.manual)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// The card grid with the FR-014c unified empty-state for no results.
public struct LibraryCardGrid: View {
    @Bindable var model: LibraryModel
    let openNote: (UUID) -> Void
    let onTrash: (UUID) -> Void
    let onRestore: (UUID) -> Void

    public init(
        model: LibraryModel,
        openNote: @escaping (UUID) -> Void,
        onTrash: @escaping (UUID) -> Void = { _ in },
        onRestore: @escaping (UUID) -> Void = { _ in }
    ) {
        self.model = model
        self.openNote = openNote
        self.onTrash = onTrash
        self.onRestore = onRestore
    }

    public var body: some View {
        if model.cards.isEmpty {
            if model.isSearching {
                // FR-014c unified empty-state — never an error (FR-011a).
                SearchNoResultsEmptyState()
            } else {
                EmptyLibraryView(model: model) {
                    Task {
                        if let id = await model.createBlankNote() {
                            openNote(id)
                        }
                    }
                }
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 10)], spacing: 10) {
                    ForEach(model.cards) { card in
                        NoteCardView(card: card) {
                            openNote(card.noteId)
                        }
                        .contextMenu {
                            if model.scope == .library {
                                Button("Move to Trash") { onTrash(card.noteId) }
                            } else {
                                Button("Restore") { onRestore(card.noteId) }
                                Button("Delete Forever", role: .destructive) { onTrash(card.noteId) }
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }
}
