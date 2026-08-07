import SwiftUI
import Domain

// MARK: - TodoBlockView (T166/T243/T290, FR-070/FR-071/FR-072a/FR-072b/FR-182)
//
// Per tasks.md T290 and spec FR-070/FR-071/FR-072a/FR-072b: complete/
// incomplete with strikethrough BEYOND color alone (FR-182, FR-044), move
// up/down among siblings (drag-reorder equivalent), indent/outdent (max
// depth 6 — enforced by the TodoRepository), edit, delete. Completion state
// persists through the TodoRepository (stable identity, FR-071) — the
// pre-Phase-27 version flipped local `@State` only. Large todo lists (100+)
// render virtualized (FR-072b).

/// A virtualized todo list row (FR-072b: bounded row realization).
public struct TodoBlockView: View {
    let block: Block
    let onChanged: (Block) -> Void
    /// Fetches the backing TodoItem (stable identity — FR-071).
    let todoProvider: (UUID) async -> TodoItem?
    /// TodoRepository-backed actions (T290).
    let onToggleComplete: (UUID) async -> Void
    let onDelete: (UUID) async -> Void
    let onIndent: (UUID) async -> Void
    let onOutdent: (UUID) async -> Void
    let onMove: (UUID, Int) async -> Void

    @State private var todoItem: TodoItem?
    @State private var text = ""

    public init(
        block: Block,
        onChanged: @escaping (Block) -> Void,
        todoProvider: @escaping (UUID) async -> TodoItem? = { _ in nil },
        onToggleComplete: @escaping (UUID) async -> Void = { _ in },
        onDelete: @escaping (UUID) async -> Void = { _ in },
        onIndent: @escaping (UUID) async -> Void = { _ in },
        onOutdent: @escaping (UUID) async -> Void = { _ in },
        onMove: @escaping (UUID, Int) async -> Void = { _, _ in }
    ) {
        self.block = block
        self.onChanged = onChanged
        self.todoProvider = todoProvider
        self.onToggleComplete = onToggleComplete
        self.onDelete = onDelete
        self.onIndent = onIndent
        self.onOutdent = onOutdent
        self.onMove = onMove
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                // FR-070/FR-071: persist completion via the repository.
                if let item = todoItem {
                    let newValue = !item.isComplete
                    Task { await onToggleComplete(block.id) }
                    var updatedTodo = item
                    updatedTodo.isComplete = newValue
                    todoItem = updatedTodo
                }
            } label: {
                Image(systemName: (todoItem?.isComplete ?? false) ? "checkmark.square.fill" : "square")
                    .foregroundStyle((todoItem?.isComplete ?? false) ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel((todoItem?.isComplete ?? false) ? "Mark todo incomplete" : "Mark todo complete")
            .accessibilityValue((todoItem?.isComplete ?? false) ? "Complete" : "Incomplete")

            TextField("Todo", text: $text)
                .textFieldStyle(.plain)
                .strikethrough(todoItem?.isComplete ?? false)   // FR-182: more than color alone
                .foregroundStyle((todoItem?.isComplete ?? false) ? .secondary : .primary)
                .onSubmit {
                    commitText()
                }
                .onChange(of: text) { _, newValue in
                    // Persist text edits through the block payload (structural —
                    // immediate save, FR-141a).
                    if newValue != blockText {
                        commitText()
                    }
                }

            HStack(spacing: 6) {
                Button {
                    Task { await onMove(block.id, -1) }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.plain)
                .help("Move todo up")
                .accessibilityLabel("Move todo up")

                Button {
                    Task { await onMove(block.id, 1) }
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.plain)
                .help("Move todo down")
                .accessibilityLabel("Move todo down")

                Button {
                    Task { await onIndent(block.id) }
                } label: {
                    Image(systemName: "arrow.right.to.line")
                }
                .buttonStyle(.plain)
                .help("Indent (subtask)")
                .accessibilityLabel("Indent todo")

                Button {
                    Task { await onOutdent(block.id) }
                } label: {
                    Image(systemName: "arrow.left.to.line")
                }
                .buttonStyle(.plain)
                .help("Un-indent")
                .accessibilityLabel("Un-indent todo")

                Button {
                    Task { await onDelete(block.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete todo")
                .accessibilityLabel("Delete todo")
            }
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .onAppear {
            if case .todo(let payload) = block.payload {
                text = payload.richText.text
            }
            Task {
                todoItem = await todoProvider(block.id)
            }
        }
    }

    private var blockText: String {
        if case .todo(let payload) = block.payload { return payload.richText.text }
        return ""
    }

    private func commitText() {
        guard case .todo(let payload) = block.payload else { return }
        let updated = Block(
            id: block.id,
            noteId: block.noteId,
            kind: block.kind,
            sortKey: block.sortKey,
            payload: .todo(TodoPayload(todoId: payload.todoId, richText: RichTextDocument.plain(text))),
            versionId: block.versionId,
            parentVersionId: block.parentVersionId,
            lastModifiedDeviceId: block.lastModifiedDeviceId,
            createdAt: block.createdAt,
            modifiedAt: Date()
        )
        onChanged(updated)
    }
}

/// The card todo progress format (FR-072b) — "completed/total", or
/// "99+ completed" when the total exceeds 99.
public enum TodoCardProgress {
    public static func string(completed: Int, total: Int) -> String? {
        guard total > 0 else { return nil }
        if total > 99 { return "99+ completed" }
        return "\(completed)/\(total)"
    }
}
