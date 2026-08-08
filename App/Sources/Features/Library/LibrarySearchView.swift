import SwiftUI
import AppKit
import Domain
import Persistence

// MARK: - LibrarySearchView (003 T020, FR-003)
//
// Per tasks.md T020: the custom search field is REPLACED by native search
// (the NSSearchField toolbar item, attached in `LibraryToolbar` — T018
// spike). This file retains the card grid (`LibraryCardGrid`), which now
// reads the FR-021 formula from `NoteCardMetrics` (T021) and hosts the
// keyboard navigation model (T027, FR-024).

/// The card grid with the FR-014c unified empty-state for no results and
/// the FR-021 adaptive column formula (003 T021).
public struct LibraryCardGrid: View {
    @Bindable var model: LibraryModel
    let openNote: (UUID) -> Void
    let onTrash: (UUID) -> Void
    let onRestore: (UUID) -> Void
    /// FR-014 (T305): the Trash-scope "Delete Forever" action — the
    /// permanent-delete path (distinct from `onTrash`; the note must leave
    /// Trash beyond recovery). The confirmation lives in this view
    /// (FR-026); the model performs the action.
    let onPermanentlyDelete: (UUID) -> Void

    /// The note awaiting single permanent-delete confirmation (FR-026).
    @State private var pendingPermanentDelete: UUID?
    /// The note awaiting Empty Trash confirmation (FR-014b).
    @State private var confirmingEmptyTrash = false

    /// FR-021 (003 T021): deterministic column count (replaces the 001
    /// fixed 3/2/1-at-600/400 constants). Content width = window width.
    public static func columnCount(forWidth width: CGFloat) -> Int {
        NoteCardMetrics.columnCount(forContentWidth: width)
    }

    /// FR-021: card width for a content width.
    public static func cardWidth(forWidth width: CGFloat) -> CGFloat {
        NoteCardMetrics.cardWidth(forContentWidth: width)
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
            } else if model.scope == .trash {
                EmptyTrashEmptyState()
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
                    // Trash destination: Empty Trash control above the grid
                    // (FR-014b, 003 T023) — visually subordinate to Notes
                    // (SC-006).
                    if model.scope == .trash {
                        HStack {
                            Spacer()
                            Button("Empty Trash…") {
                                confirmingEmptyTrash = true
                            }
                            .controlSize(.small)
                            .accessibilityLabel("Empty Trash")
                        }
                        .padding(.horizontal, NoteCardMetrics.spacing)
                        .padding(.top, NoteCardMetrics.spacing)
                    }

                    LazyVGrid(
                        columns: Self.columns(forWidth: geometry.size.width),
                        spacing: NoteCardMetrics.spacing
                    ) {
                        ForEach(model.cards) { card in
                            NoteCardView(
                                card: card,
                                isKeyboardSelected: model.keyboardSelection == card.noteId,
                                action: {
                                    openNote(card.noteId)
                                }
                            )
                            .contextMenu {
                                if model.scope == .library {
                                    Button("Move to Trash") { onTrash(card.noteId) }
                                } else {
                                    Button("Restore") { onRestore(card.noteId) }
                                    // FR-026 (003 T023): single permanent
                                    // delete is CONFIRMED first.
                                    Button("Delete Forever", role: .destructive) {
                                        pendingPermanentDelete = card.noteId
                                    }
                                }
                            }
                        }
                    }
                    .padding(NoteCardMetrics.spacing)
                }
                // FR-026: explicit single permanent-delete confirmation with
                // the 30-day guarantee loss clause (CHK013).
                .confirmationDialog(
                    DeletionConfirmationPolicy.confirmation(for: .permanentDeleteSingle)?.message ?? "",
                    isPresented: Binding(
                        get: { pendingPermanentDelete != nil },
                        set: { if !$0 { pendingPermanentDelete = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete Forever", role: .destructive) {
                        if let noteId = pendingPermanentDelete {
                            onPermanentlyDelete(noteId)
                        }
                        pendingPermanentDelete = nil
                    }
                    Button("Cancel", role: .cancel) {
                        pendingPermanentDelete = nil
                    }
                }
                // FR-014b: Empty Trash confirmation (Trash destination).
                .confirmationDialog(
                    DeletionConfirmationPolicy.confirmation(for: .emptyTrash)?.message ?? "",
                    isPresented: $confirmingEmptyTrash,
                    titleVisibility: .visible
                ) {
                    Button("Empty Trash", role: .destructive) {
                        Task { _ = await model.emptyTrash() }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                // FR-024 (003 T027): arrow-key selection + Return open +
                // ⌘⌫ move-to-Trash. The card grid's keyboard model is
                // distinct from the toolbar Tab order (CHK004).
                .focusable()
                .onKeyPress(.upArrow) {
                    model.moveKeyboardSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    model.moveKeyboardSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    model.moveKeyboardSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    model.moveKeyboardSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.return) {
                    if let selected = model.keyboardSelection {
                        openNote(selected)
                    }
                    return .handled
                }
                .onKeyPress(keys: [.delete]) { _ in
                    if let selected = model.keyboardSelection, model.scope == .library {
                        onTrash(selected)
                    }
                    return .handled
                }
            }
        }
    }

    /// FR-021: deterministic columns from the formula.
    public static func columns(forWidth width: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: NoteCardMetrics.spacing),
            count: NoteCardMetrics.columnCount(forContentWidth: width)
        )
    }
}
