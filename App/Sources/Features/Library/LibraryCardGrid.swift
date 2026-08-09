import SwiftUI
import AppKit
import Domain
import Persistence

// MARK: - LibraryCardGrid (003 T020/T082, FR-003)
//
// Per tasks.md T020: search lives in the `MenuBarLibraryScene` control row
// (方案 B — the T018 NSToolbar spike concluded; `LibraryToolbar` removed).
// This file retains the card grid (`LibraryCardGrid`), which reads the
// FR-021 formula from `NoteCardMetrics` (T021) and hosts the keyboard
// navigation model (T027, FR-024).

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
        // FR-026 / FR-014b: confirmations are IN-WINDOW inline bars, NOT
        // SwiftUI `confirmationDialog`. Verified 2026-08-09 on macOS 27:
        // a confirmationDialog inside a MenuBarExtra(.window) presents
        // INVERTED — the library window becomes a sheet of a detached
        // `_NSAlertPanel` (`attachedSheet` = library window). Clicking the
        // destructive button dismisses the alert, which force-ends its
        // sheet → the library window closes before the action closure
        // runs (state never resets; the dialog re-presents on reopen).
        // In-window bars keep every click inside the library window.
        gridContent
    }

    /// The scope-dependent content (grid or empty-state). The
    /// confirmation dialogs must NOT live here — see `body`.
    @ViewBuilder
    private var gridContent: some View {
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
                    // FR-026 (003 T023): the pending single permanent-delete
                    // confirmation shows as an in-window bar above the grid
                    // (see `body` for why dialogs are avoided).
                    if let noteId = pendingPermanentDelete {
                        InlineConfirmationBar(
                            message: DeletionConfirmationPolicy.confirmation(for: .permanentDeleteSingle)?.message ?? "",
                            confirmTitle: "Delete Forever"
                        ) {
                            pendingPermanentDelete = nil
                            onPermanentlyDelete(noteId)
                        } onCancel: {
                            pendingPermanentDelete = nil
                        }
                    }

                    // Trash destination: Empty Trash control above the grid
                    // (FR-014b, 003 T023) — visually subordinate to Notes
                    // (SC-006). The confirm step replaces the button in
                    // place (in-window, FR-026).
                    if model.scope == .trash {
                        if confirmingEmptyTrash {
                            InlineConfirmationBar(
                                message: DeletionConfirmationPolicy.confirmation(for: .emptyTrash)?.message ?? "",
                                confirmTitle: "Empty Trash"
                            ) {
                                confirmingEmptyTrash = false
                                Task { _ = await model.emptyTrash() }
                            } onCancel: {
                                confirmingEmptyTrash = false
                            }
                        } else {
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
                            // Verified 2026-08-09: without explicit identity
                            // the grid can draw a removed card once at its
                            // stale slot while relaying out. The transition
                            // makes deletions (FR-014/FR-026) fade+shrink
                            // out instead of snapping away.
                            .id(card.noteId)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity,
                                    removal: .scale(scale: 0.9).combined(with: .opacity)
                                )
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
                // FR-024 (003 T027): arrow-key selection + Return open +
                // ⌘⌫ move-to-Trash. The card grid's keyboard model is
                // distinct from the toolbar Tab order (CHK004). The focus
                // RING is disabled (verified 2026-08-09: clicking the
                // panel's content focused this ScrollView and drew a vivid
                // full-width accent line under the toolbar; it flickered
                // as focus churned). Keyboard navigation stays.
                .focusable()
                .focusEffectDisabled()
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
                .onKeyPress(.escape) {
                    if pendingPermanentDelete != nil {
                        pendingPermanentDelete = nil
                    }
                    if confirmingEmptyTrash {
                        confirmingEmptyTrash = false
                    }
                    return pendingPermanentDelete == nil && !confirmingEmptyTrash
                        ? .ignored
                        : .handled
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

/// In-window destructive-action confirmation bar (FR-026). Used instead of
/// SwiftUI `confirmationDialog` — on macOS 27 a dialog in a MenuBarExtra
/// window inverts the sheet relationship and closes the library window
/// when its destructive button is clicked (see `LibraryCardGrid.body`).
private struct InlineConfirmationBar: View {
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(confirmTitle, role: .destructive, action: onConfirm)
                .controlSize(.small)
            Button("Cancel", role: .cancel, action: onCancel)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .padding(.horizontal, NoteCardMetrics.spacing)
        .padding(.top, NoteCardMetrics.spacing)
        .accessibilityElement(children: .contain)
    }
}
