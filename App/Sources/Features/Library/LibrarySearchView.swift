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
    /// FR-014 (T305): the Trash-scope "Delete Forever" action — the
    /// permanent-delete path (distinct from `onTrash`; the note must leave
    /// Trash beyond recovery).
    let onPermanentlyDelete: (UUID) -> Void

    /// FR-002a: card width ≈ 220 pt, height ≈ 160 pt, 12 pt inter-card
    /// spacing.
    public static let cardApproximateWidth: CGFloat = 220
    public static let cardApproximateHeight: CGFloat = 160
    public static let interCardSpacing: CGFloat = 12

    /// FR-002a responsive breakpoints: 3 columns at ≥600 pt, 2 below 600,
    /// 1 below 400.
    public static func columnCount(forWidth width: CGFloat) -> Int {
        if width >= 600 { return 3 }
        if width >= 400 { return 2 }
        return 1
    }

    public init(
        model: LibraryModel,
        openNote: @escaping (UUID) -> Void,
        onTrash: @escaping (UUID) -> Void = { _ in },
        onRestore: @escaping (UUID) -> Void = { _ in },
        onPermanentlyDelete: @escaping (UUID) -> Void = { _ in }
    ) {
        self.model = model
        self.openNote = openNote
        self.onTrash = onTrash
        self.onRestore = onRestore
        self.onPermanentlyDelete = onPermanentlyDelete
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
            GeometryReader { geometry in
                ScrollView {
                    LazyVGrid(
                        columns: Self.columns(forWidth: geometry.size.width),
                        spacing: Self.interCardSpacing
                    ) {
                        ForEach(model.cards) { card in
                            NoteCardView(card: card) {
                                openNote(card.noteId)
                            }
                            .contextMenu {
                                if model.scope == .library {
                                    Button("Move to Trash") { onTrash(card.noteId) }
                                } else {
                                    Button("Restore") { onRestore(card.noteId) }
                                    Button("Delete Forever", role: .destructive) { onPermanentlyDelete(card.noteId) }
                                }
                            }
                        }
                    }
                    .padding(Self.interCardSpacing)
                }
            }
        }
    }

    /// FR-002a: 3 columns at ≥600 pt, 2 below 600, 1 below 400; 12 pt
    /// inter-card spacing.
    public static func columns(forWidth width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: interCardSpacing), count: columnCount(forWidth: width))
    }
}
