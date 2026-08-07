import SwiftUI
import Domain

// MARK: - TrashView (T167/T231/T270)
//
// Per tasks.md T167/T231/T270 and spec FR-014/FR-014a/FR-014b/FR-014c:
// list Trash, restore, permanently delete, distinguish Trash/permanent-
// deleted/recovered-conflict-copy/active states; Empty Trash batch action
// (FR-014b) with explicit confirmation stating immediate permanent deletion
// and loss of the 30-day guarantee; the unified empty-state (FR-014c) when
// Trash is empty.

public struct TrashView: View {
    @Bindable var model: LibraryModel

    public init(model: LibraryModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            if model.cards.isEmpty {
                EmptyTrashEmptyState()
            } else {
                List(model.cards) { card in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(card.title ?? card.summary ?? "Untitled")
                                .font(.callout)
                            Text(DisplayFormatters.lastModified(card.modifiedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") {
                            Task { await model.restore(noteId: card.noteId) }
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Restore note")

                        Button("Delete Forever") {
                            Task { await model.permanentlyDelete(noteId: card.noteId) }
                        }
                        .controlSize(.small)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Permanently delete note")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Trash")
                .font(.headline)
            Spacer()
            if !model.cards.isEmpty {
                Button("Empty Trash…") {
                    confirmEmptyTrash()
                }
                .controlSize(.small)
                // FR-014b: explicit confirmation stating the outcome.
                .confirmationDialog(
                    "Empty Trash permanently deletes all notes in Trash immediately. The 30-day recoverability guarantee no longer applies.",
                    isPresented: $showingEmptyTrashConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Empty Trash", role: .destructive) {
                        Task { _ = await model.emptyTrash() }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .accessibilityLabel("Empty Trash")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @State private var showingEmptyTrashConfirmation = false

    private func confirmEmptyTrash() {
        showingEmptyTrashConfirmation = true
    }
}
