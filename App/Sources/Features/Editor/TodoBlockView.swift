import SwiftUI
import Domain
import EditorCore
import SystemBridge

// MARK: - Todo first-line-center alignment (004 修复 2026-08-14, P1)
//
// The todo row compares two CENTERS: the checkbox's visual center and the
// first text line's typographic center. Borrowing `.firstTextBaseline`
// would force "baseline == baseline" semantics and push the center math
// into the guide values; a dedicated alignment makes the contract literal:
//
//   marker visual center  ──── same axis ────  first line typographic center

private enum TodoFirstLineCenterAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context[VerticalAlignment.center]
    }
}

private extension VerticalAlignment {
    static let todoFirstLineCenter = VerticalAlignment(TodoFirstLineCenterAlignment.self)
}

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
    /// Phase 3: the resolved typography VALUE (font preference + spacing
    /// + per-note text size) — threaded into the todo's rich-text editor.
    let editorTypography: EditorTypography
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
    /// 2026-08-14 (Q2-A/Q3-B): DELETE key on an empty todo — host-side
    /// removal (TodoItem-row cascade) + focus to the next block's start.
    let onDeleteEmptyBlock: (() -> Void)?
    /// 2026-08-14 (Q4-A): first-character Backspace merges the todo into
    /// the previous block.
    let onMergeIntoPrevious: (() -> Void)?
    /// 2026-08-14 (Q5-A/Q6-B): todo-tail Return → insert an empty paragraph
    /// block after this todo.
    let onInsertParagraphAfterSelf: (() -> Void)?
    /// 2026-08-14 (Q8-B): ⌘A in the todo editor selects the whole note.
    let onSelectAllInNote: (() -> Void)?
    /// 2026-08-14: 跨块模式下 Backspace/Delete → host 跨块删除。
    let onDeleteSpanningSelection: (() -> Void)?
    /// R2.2 (Phase 2): ⌘C 跨块复制透传。
    let onCopySpanningSelection: ((CrossBlockSelection) -> Void)?
    /// 004 修复: host undo/redo revision — re-fetches the TodoItem so the
    /// checkbox follows structural undo/redo.
    let todoRevision: Int

    @State private var todoItem: TodoItem?
    // 004 修复 (P1-5): the trailing controls collapse into ONE hover-gated
    // ellipsis menu (was five always-visible buttons).
    @State private var isHoveringRow = false
    // 004 修复 (2026-08-14, P1): the first text line's typographic center
    // (published by the editor from REAL TextKit geometry) — the
    // checkbox's visual center aligns to it. Seeded with the nominal
    // font's metric-derived center so the FIRST frame is already correct;
    // the published value (≈ the same) lands on the next runloop turn.
    @State private var firstLineCenterY: CGFloat

    public init(
        block: Block,
        editorTypography: EditorTypography,
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
        onDeleteEmptyBlock: (() -> Void)? = nil,
        onMergeIntoPrevious: (() -> Void)? = nil,
        onInsertParagraphAfterSelf: (() -> Void)? = nil,
        onSelectAllInNote: (() -> Void)? = nil,
        onDeleteSpanningSelection: (() -> Void)? = nil,
        onCopySpanningSelection: ((CrossBlockSelection) -> Void)? = nil,
        todoRevision: Int = 0
    ) {
        self.block = block
        self.editorTypography = editorTypography
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
        self.onDeleteEmptyBlock = onDeleteEmptyBlock
        self.onMergeIntoPrevious = onMergeIntoPrevious
        self.onInsertParagraphAfterSelf = onInsertParagraphAfterSelf
        self.onSelectAllInNote = onSelectAllInNote
        self.onDeleteSpanningSelection = onDeleteSpanningSelection
        self.onCopySpanningSelection = onCopySpanningSelection
        self.todoRevision = todoRevision
        // 004 修复 (2026-08-14, P1): the first-frame seed — the nominal
        // body font's line center (ascender−descender)/2. PR1: the seed and
        // the published metric share ONE source (`nominalBodyFont`) — the
        // published baseline-based value differs from the seed only by the
        // REAL layout baseline, so the first frame is already correct.
        let seedFont = NoteFontResolver(preference: editorTypography.fontPreference)
            .nominalBodyFont(size: editorTypography.textSize)
        _firstLineCenterY = State(initialValue: (seedFont.ascender - seedFont.descender) / 2)
    }

    public var body: some View {
        let isComplete = todoItem?.isComplete ?? false
        // Plain value captured by the @Sendable alignmentGuide closure
        // below (Swift 6: the view's isolated property cannot be
        // referenced from it directly).
        let centerY = firstLineCenterY
        HStack(alignment: .todoFirstLineCenter, spacing: BlockLayoutMetrics.todoMarkerGap) {
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
            // 004 修复 (2026-08-14, P1): THREE separated sizes —
            // visual marker (the symbol's native ~13pt size),
            // interaction target (todoMarkerHitSize, an oversized inner
            // frame), layout column (todoMarkerColumnWidth, the outer
            // frame). The hit target overflows the column (3pt each side,
            // landing in the paper margin / inter-block gap — never on
            // content) WITHOUT widening the HStack child: the todo text
            // leading = paperInset + column + gap, invariant.
            .frame(
                width: BlockLayoutMetrics.todoMarkerHitSize,
                height: BlockLayoutMetrics.todoMarkerHitSize
            )
            .contentShape(Rectangle())
            .frame(width: BlockLayoutMetrics.todoMarkerColumnWidth, alignment: .center)
            // The marker's visual center sits ON the first line's
            // typographic center (custom center-to-center alignment —
            // multi-line todos keep the marker with their FIRST line).
            .alignmentGuide(.todoFirstLineCenter) { d in
                d.height / 2
            }
            .accessibilityLabel(isComplete ? "Mark todo incomplete" : "Mark todo complete")
            .accessibilityValue(isComplete ? "Complete" : "Incomplete")

            // 004 修复: the todo text is a rich-text editor in the unified
            // editing context (marks/undo/focus/⌘B/⌘I). Completion styling
            // is display-only.
            RichTextView(
                document: todoDocument,
                editorTypography: editorTypography,
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
                onFirstLineTypographicCenter: { center in
                    // Defer out of the view-update pass — mutating @State
                    // inside updateNSView's callback is undefined behavior
                    // (SwiftUI warns); the async hop lands it on the next
                    // runloop turn, where the alignment settles.
                    DispatchQueue.main.async {
                        firstLineCenterY = center
                    }
                },
                requestFocus: requestFocus,
                caretAtEnd: caretAtEnd,
                onFocusRequestHandled: onFocusRequestHandled,
                onDeleteEmptyBlock: onDeleteEmptyBlock,
                onMergeIntoPrevious: onMergeIntoPrevious,
                onInsertParagraphAfterSelf: onInsertParagraphAfterSelf,
                onSelectAllInNote: onSelectAllInNote,
                onDeleteSpanningSelection: onDeleteSpanningSelection,
                onCopySpanningSelection: onCopySpanningSelection
            )
            // Pin the vertical size to the editor's intrinsic — the row
            // proposes its full height (marker hit frame + alignment
            // offset) and a flexible representable would accept it,
            // growing 3pt of dead space at the frame's bottom. Horizontal
            // stays proposed (the width reflow depends on it).
            .fixedSize(horizontal: false, vertical: true)
            .alignmentGuide(.todoFirstLineCenter) { _ in
                centerY
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