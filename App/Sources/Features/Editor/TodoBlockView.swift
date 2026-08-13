import SwiftUI
import Domain
import SystemBridge

// MARK: - TodoBlockView (T166/T243/T290, FR-070/FR-071/FR-072a/FR-072b/FR-182)
//
// Per tasks.md T290 and spec FR-070/FR-071/FR-072a/FR-072b: complete/
// incomplete with strikethrough BEYOND color alone (FR-182, FR-044), move
// up/down among siblings (drag-reorder equivalent), indent/outdent (max
// depth 6 — enforced by the TodoRepository), edit, delete. Completion state
// persists through the TodoRepository (stable identity, FR-071) — the
// pre-Phase-27 version flipped local `@State` only. Large todo lists (100+)
// render virtualized (FR-072b).
//
// 004 修复 (2026-08-13): the todo TEXT is a full rich-text surface — a
// RichTextView (not a plain TextField), so run marks survive edits
// (FR-053), ⌘B/⌘I work, typing undo lands on the window-level shared
// UndoManager, and focus publishes `focusedSpecialBlockId` (insertion
// targets `.afterBlock` — FR-010). Completion strikethrough/secondary
// color is display-only styling (EditorDisplayStyling — never a model
// mark).

/// A virtualized todo list row (FR-072b: bounded row realization).
public struct TodoBlockView: View {
    let block: Block
    let textSize: CGFloat
    let onChanged: (Block) -> Void
    /// Fetches the backing TodoItem (stable identity — FR-071).
    let todoProvider: (UUID) async -> TodoItem?
    /// TodoRepository-backed actions (T290).
    let onToggleComplete: (UUID) async -> Void
    let onDelete: (UUID) async -> Void
    let onIndent: (UUID) async -> Void
    let onOutdent: (UUID) async -> Void
    let onMove: (UUID, Int) async -> Void
    /// 004 修复: unified editing context wiring.
    let selectionBridge: EditorSelectionBridge?
    let undoManager: UndoManager?
    let requestFocus: Bool
    /// 004 修复 (2026-08-14, P0): caret position forwarded to the todo's
    /// rich-text editor (tail continuation never targets todos in
    /// practice; the contract stays uniform).
    let caretAtEnd: Bool
    let onFocusRequestHandled: () -> Void
    /// 004 修复 (P1-6): focus transitions of the todo text editor — the
    /// host applies the FR-050a empty-block exit (with TodoItem-row undo
    /// integrity).
    let onFocusChange: (Bool, Bool) -> Void
    /// 004 修复: host undo/redo revision — re-fetches the TodoItem so the
    /// checkbox follows structural undo/redo.
    let todoRevision: Int

    @State private var todoItem: TodoItem?
    // 004 修复 (P1-5): the trailing controls collapse into ONE hover-gated
    // ellipsis menu (was five always-visible buttons).
    @State private var isHoveringRow = false

    public init(
        block: Block,
        textSize: CGFloat = 13,
        onChanged: @escaping (Block) -> Void,
        todoProvider: @escaping (UUID) async -> TodoItem? = { _ in nil },
        onToggleComplete: @escaping (UUID) async -> Void = { _ in },
        onDelete: @escaping (UUID) async -> Void = { _ in },
        onIndent: @escaping (UUID) async -> Void = { _ in },
        onOutdent: @escaping (UUID) async -> Void = { _ in },
        onMove: @escaping (UUID, Int) async -> Void = { _, _ in },
        selectionBridge: EditorSelectionBridge? = nil,
        undoManager: UndoManager? = nil,
        requestFocus: Bool = false,
        caretAtEnd: Bool = false,
        onFocusRequestHandled: @escaping () -> Void = {},
        onFocusChange: @escaping (Bool, Bool) -> Void = { _, _ in },
        todoRevision: Int = 0
    ) {
        self.block = block
        self.textSize = textSize
        self.onChanged = onChanged
        self.todoProvider = todoProvider
        self.onToggleComplete = onToggleComplete
        self.onDelete = onDelete
        self.onIndent = onIndent
        self.onOutdent = onOutdent
        self.onMove = onMove
        self.selectionBridge = selectionBridge
        self.undoManager = undoManager
        self.requestFocus = requestFocus
        self.caretAtEnd = caretAtEnd
        self.onFocusRequestHandled = onFocusRequestHandled
        self.onFocusChange = onFocusChange
        self.todoRevision = todoRevision
    }

    public var body: some View {
        let isComplete = todoItem?.isComplete ?? false
        // Plain values captured by the @Sendable alignmentGuide closures
        // below (Swift 6: the view's isolated properties cannot be
        // referenced from them directly).
        let lineCenter = lineCenterOffset
        // The todo editor's first-line baseline is DETERMINISTIC (no state
        // round trip): its text container has zero inset and zero line
        // fragment padding, so the first line starts at the view's top —
        // the baseline is exactly the body font's ascender.
        let baseline = textBaseline
        HStack(alignment: .firstTextBaseline, spacing: BlockLayoutMetrics.todoMarkerGap) {
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
                Image(systemName: isComplete ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isComplete ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            // 004 修复 (2026-08-14, P0): THREE separated sizes —
            // visual marker (the symbol's intrinsic size), the layout
            // marker COLUMN (fixed gutter width), and the interaction hit
            // target (the whole column via contentShape). Expanding the
            // hit target never widens the column, so the todo text
            // leading (paperInset + column + gap) never drifts.
            .frame(width: BlockLayoutMetrics.todoMarkerColumnWidth, alignment: .center)
            .contentShape(Rectangle())
            // The checkbox's visual center sits on the FIRST line's
            // vertical center (baseline − (ascender−descender)/2), so a
            // multi-line todo keeps the marker with its first line —
            // never the whole row's center.
            .alignmentGuide(.firstTextBaseline) { d in
                d.height / 2 + lineCenter
            }
            .accessibilityLabel(isComplete ? "Mark todo incomplete" : "Mark todo complete")
            .accessibilityValue(isComplete ? "Complete" : "Incomplete")

            // 004 修复: the todo text is a rich-text editor in the unified
            // editing context (marks/undo/focus/⌘B/⌘I). Completion styling
            // is display-only.
            RichTextView(
                document: todoDocument,
                textSize: textSize,
                onCommit: { document in
                    commitText(document)
                },
                onFocusChange: onFocusChange,
                selectionBridge: selectionBridge,
                richTextBlockId: block.id,
                undoManager: undoManager,
                minimumHeight: 0,
                // 004 修复 (第二轮): no vertical inset — the 12pt top inset
                // floated the checkbox above the text's ink line and the
                // bottom inset doubled the row-to-row rhythm.
                verticalInset: 0,
                isSpecialBlock: true,
                displayStyling: EditorDisplayStyling(strikethrough: isComplete, secondaryColor: isComplete),
                requestFocus: requestFocus,
                caretAtEnd: caretAtEnd,
                onFocusRequestHandled: onFocusRequestHandled
            )
            .alignmentGuide(.firstTextBaseline) { _ in
                baseline
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // 004 修复 (P1-5): ONE hover-gated ellipsis menu replaces the
            // five always-visible buttons (the FileReferenceCardView menu
            // pattern). The invisible state keeps its layout slot so the
            // row width never jumps on hover.
            Menu {
                Button("Move Up") { Task { await onMove(block.id, -1) } }
                Button("Move Down") { Task { await onMove(block.id, 1) } }
                Button("Indent") { Task { await onIndent(block.id) } }
                Button("Outdent") { Task { await onOutdent(block.id) } }
                Divider()
                Button("Delete", role: .destructive) { Task { await onDelete(block.id) } }
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.plain)
            .help("Todo actions")
            .accessibilityLabel("Todo actions")
            .opacity(isHoveringRow ? 1 : 0)
            .allowsHitTesting(isHoveringRow)
        }
        .onHover { hovering in
            isHoveringRow = hovering
        }
        .task(id: todoRevision) {
            // Re-fetches on appear AND after structural undo/redo (the
            // revision bumps so the checkbox follows ⌘Z/⌘⇧Z).
            todoItem = await todoProvider(block.id)
        }
    }

    /// The todo's rich-text document (todo text keeps run marks — FR-053).
    private var todoDocument: RichTextDocument {
        if case .todo(let payload) = block.payload { return payload.richText }
        return .empty
    }

    /// The first line's vertical center distance from its baseline —
    /// derived from the body font's REAL metrics (ascender/descender),
    /// never a magic offset (004 修复 2026-08-14, P0).
    private var lineCenterOffset: CGFloat {
        let font = bodyFont
        return (font.ascender - font.descender) / 2
    }

    /// The todo editor's first-line baseline: its text container carries
    /// zero inset and zero line-fragment padding, so the first line starts
    /// at the view's top — the baseline is exactly the body font's
    /// ascender. Deterministic (no layout-manager state round trip through
    /// a SwiftUI @State, which positioned the row one pass late).
    private var textBaseline: CGFloat {
        bodyFont.ascender
    }

    /// The todo text's body font (the same resolver the RichTextView
    /// uses for the note text at `textSize`).
    private var bodyFont: NSFont {
        NoteFontResolver.load().font(size: textSize, for: "")
    }

    private func commitText(_ document: RichTextDocument) {
        guard case .todo(let payload) = block.payload else { return }
        let updated = Block(
            id: block.id,
            noteId: block.noteId,
            kind: block.kind,
            sortKey: block.sortKey,
            payload: .todo(TodoPayload(todoId: payload.todoId, richText: document)),
            versionId: block.versionId,
            parentVersionId: block.parentVersionId,
            lastModifiedDeviceId: DeviceIdentity.current.id,
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
