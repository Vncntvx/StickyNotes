import SwiftUI
import AppKit
import Domain
import EditorCore
import Persistence
import SystemBridge

// MARK: - RichTextBlockView (T161/T211/T259)
//
// Per tasks.md T161/T211/T259 and spec FR-050/FR-051/FR-052/FR-053/FR-054/
// FR-060/FR-061/FR-062/FR-063 + 004 redesign:
// - 004 T017 (FR-003): the title field lives at the top of the note paper
//   (the window titlebar shows a DERIVED display title; editing happens
//   here — 001 FR-050 "optional title" semantics).
// - 004 (FR-010): caret-split insertions produce a trailing rich-text
//   block — every rich-text block AFTER the primary surface renders as an
//   editable block (the primary surface stays the first one).
// - 004 T034 (FR-010/FR-043): the insertion-point context control's
//   triggers (cursor-line hover + text selection) are actually wired.

/// The rich-text block editor (one note = one seamless rich-text block
/// surface per note window; special blocks are rendered around it by the
/// host).
public struct RichTextBlockView: View {
    let note: Note
    let blocks: [Block]
    /// 004 T017: appearance edits (title field) — persisted immediately by
    /// the host.
    let onAppearanceChange: (Note) -> Void
    let onBlocksChanged: ([Block]) -> Void
    /// Structural changes (todo toggle, block insert/delete/reorder) — saved
    /// immediately per FR-141a (T281).
    let onStructuralBlocksChanged: ([Block]) -> Void

    // T290: block-editing affordances (insertion + per-block actions),
    // wired by the note-window host.
    let onInsertTodo: () -> Void
    let onInsertCode: () -> Void
    let onInsertFileReference: () -> Void
    let onCaptureScreenshot: () -> Void
    let todoProvider: (UUID) async -> TodoItem?
    let onToggleTodo: (UUID) async -> Void
    let onDeleteTodo: (UUID) async -> Void
    let onIndentTodo: (UUID) async -> Void
    let onOutdentTodo: (UUID) async -> Void
    let onMoveTodo: (UUID, Int) async -> Void
    /// 004 修复 (P1-6): FR-050a empty-block exit for todo blocks — routed
    /// through the host so the cascade-deleted TodoItem row restores in the
    /// same undo group as the block.
    let onEmptyTodoExit: (UUID) async -> Void
    /// 004 修复 (第二轮): the code block's delete affordance (the hover
    /// ellipsis menu) — routed through the host's structural deletion (ONE
    /// undo group, FR-141a immediate persist).
    let onDeleteCode: (UUID) async -> Void
    let onFileAction: (UUID, FileReferenceAction) async -> Void
    let onSetCover: (UUID?, Bool) async -> Void
    let onUpdateCaption: (UUID, String?) async -> Void
    let onOpenViewer: () -> Void
    let onEmbeddedImageAction: (UUID, EmbeddedImageAction) async -> Void
    /// 004 修复: the window-level shared UndoManager (threaded into every
    /// block editor — primary/trailing/todo/code).
    let undoManager: UndoManager?
    /// 004 修复: document-level focus request — the target block's editor
    /// becomes first responder (caret at the requested position).
    let focusRequest: EditorFocusRequest?
    let onFocusRequestHandled: () -> Void
    /// 004 修复 (2026-08-14, P0): the document tail was clicked — the host
    /// focuses the existing trailing paragraph or materializes a new one.
    let onContinueDocument: () -> Void
    /// 004 修复: host undo/redo revision — todo rows re-fetch their
    /// TodoItem state when structural undo/redo changes it.
    let todoRevision: Int

    @State private var isIMEComposing = false
    // T300 (FR-050a): cursor-exit detection for empty-block removal. The
    // decision fires exactly once per exit; the flag resets when the block
    // gains non-empty text again.
    @State private var didRemoveEmptyBlockOnExit = false
    // 003 T031 (CHK008): the insertion-point context control's presentation
    // triggers — cursor-line hover and text selection.
    @State private var isCursorLineHovered = false
    // 004 T037: the per-window selection bridge (shared with the toolbar's
    // insertion-target resolution).
    @State private var selectionBridge: EditorSelectionBridge?
    // 004 T063: the measured paper width (ScrollView viewport) feeding the
    // FR-019 semantic insets — measured via onGeometryChange, NOT a
    // wrapping GeometryReader (which would pin content height to the
    // viewport and break vertical scrolling).
    @State private var paperWidth: CGFloat = 480
    // 004 修复 (2026-08-14, P0): the ScrollView viewport HEIGHT — the
    // document content fills at least the viewport so the tail
    // continuation region reaches the bottom of a short note's paper.
    @State private var viewportHeight: CGFloat = 0
    // 004 修复: the pending focus request consumed by the target block's
    // editor (cleared when handled).
    @State private var pendingFocus: EditorFocusRequest?

    public init(
        note: Note,
        blocks: [Block],
        onAppearanceChange: @escaping (Note) -> Void = { _ in },
        onBlocksChanged: @escaping ([Block]) -> Void,
        onStructuralBlocksChanged: @escaping ([Block]) -> Void = { _ in },
        onInsertTodo: @escaping () -> Void = {},
        onInsertCode: @escaping () -> Void = {},
        onInsertFileReference: @escaping () -> Void = {},
        onCaptureScreenshot: @escaping () -> Void = {},
        todoProvider: @escaping (UUID) async -> TodoItem? = { _ in nil },
        onToggleTodo: @escaping (UUID) async -> Void = { _ in },
        onDeleteTodo: @escaping (UUID) async -> Void = { _ in },
        onIndentTodo: @escaping (UUID) async -> Void = { _ in },
        onOutdentTodo: @escaping (UUID) async -> Void = { _ in },
        onMoveTodo: @escaping (UUID, Int) async -> Void = { _, _ in },
        onEmptyTodoExit: @escaping (UUID) async -> Void = { _ in },
        onDeleteCode: @escaping (UUID) async -> Void = { _ in },
        onFileAction: @escaping (UUID, FileReferenceAction) async -> Void = { _, _ in },
        onSetCover: @escaping (UUID?, Bool) async -> Void = { _, _ in },
        onUpdateCaption: @escaping (UUID, String?) async -> Void = { _, _ in },
        onOpenViewer: @escaping () -> Void = {},
        onEmbeddedImageAction: @escaping (UUID, EmbeddedImageAction) async -> Void = { _, _ in },
        undoManager: UndoManager? = nil,
        focusRequest: EditorFocusRequest? = nil,
        onFocusRequestHandled: @escaping () -> Void = {},
        onContinueDocument: @escaping () -> Void = {},
        todoRevision: Int = 0
    ) {
        self.note = note
        self.blocks = blocks
        self.onAppearanceChange = onAppearanceChange
        self.onBlocksChanged = onBlocksChanged
        self.onStructuralBlocksChanged = onStructuralBlocksChanged
        self.onInsertTodo = onInsertTodo
        self.onInsertCode = onInsertCode
        self.onInsertFileReference = onInsertFileReference
        self.onCaptureScreenshot = onCaptureScreenshot
        self.todoProvider = todoProvider
        self.onToggleTodo = onToggleTodo
        self.onDeleteTodo = onDeleteTodo
        self.onIndentTodo = onIndentTodo
        self.onOutdentTodo = onOutdentTodo
        self.onMoveTodo = onMoveTodo
        self.onEmptyTodoExit = onEmptyTodoExit
        self.onDeleteCode = onDeleteCode
        self.onFileAction = onFileAction
        self.onSetCover = onSetCover
        self.onUpdateCaption = onUpdateCaption
        self.onOpenViewer = onOpenViewer
        self.onEmbeddedImageAction = onEmbeddedImageAction
        self.undoManager = undoManager
        self.focusRequest = focusRequest
        self.onFocusRequestHandled = onFocusRequestHandled
        self.onContinueDocument = onContinueDocument
        self.todoRevision = todoRevision
        _pendingFocus = State(initialValue: focusRequest)
    }

    public var body: some View {
        ScrollView {
            paper
                // 004 修复 (2026-08-14, P0): the document content fills at
                // least the viewport (minus the paper's top/bottom insets)
                // so the tail Spacer absorbs the remaining visible paper —
                // the whole tail is the continuation click target.
                // A min-height floor, never a pin: longer notes still
                // scroll naturally.
                .frame(
                    minHeight: max(
                        0,
                        viewportHeight
                            - BlockLayoutMetrics.paperTopInset
                            - BlockLayoutMetrics.paperBottomInset
                    ),
                    alignment: .top
                )
                .padding(.horizontal, inset)
                .padding(.bottom, BlockLayoutMetrics.paperBottomInset)
                .padding(.top, BlockLayoutMetrics.paperTopInset)
        }
        // 004 T063 (2026-08-13 fix): the width-sensing GeometryReader
        // previously WRAPPED the content — it accepted the ScrollView's
        // viewport height proposal, so long notes were clipped at the
        // viewport and could not scroll. Width is now measured via
        // onGeometryChange (no wrapping); the content VStack sizes itself
        // from its children (the NSTextView's intrinsic height grows with
        // the text), so the ScrollView scrolls naturally. Height is
        // measured alongside (004 修复 2026-08-14) for the tail fill.
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            paperWidth = size.width
            viewportHeight = size.height
        }
        // 004 修复: a fresh insertion-focus request becomes the pending
        // focus consumed by the new block's editor.
        .onChange(of: focusRequest) { _, newValue in
            pendingFocus = newValue
        }
        // 004 T037: the selection bridge (per window, @State — created
        // here so the primary editor can publish into it).
        .task {
            if selectionBridge == nil {
                selectionBridge = EditorSelectionBridge(noteId: note.id)
            }
        }
        // 004 T039 (FR-012) + 2026-08-10 fix: the contextual format row is
        // anchored at the AppKit level (topmost window-content subview via
        // ContextualFormatOverlayAnchor) so it is hit-testable above the
        // NSTextView — a SwiftUI overlay here could be drawn but never
        // clicked (AppKit hit testing stops at the editor's real NSView).
        // Position follows the bridge's window-coordinate selection rect.
        .overlay {
            if let bridge = selectionBridge {
                ContextualFormatOverlayAnchor(bridge: bridge)
            }
        }
    }

    // MARK: - 004 T042 semantic insets (FR-019)

    /// The FR-019 semantic content inset — the metrics' single
    /// width-aware rule (compact 10pt below 480pt, regular above, cap 24).
    private var inset: CGFloat {
        BlockLayoutMetrics.paperInset(for: paperWidth)
    }

    /// The paper content: title → insertion control → ordered blocks. Sizes
    /// itself from its children — NOT wrapped in a GeometryReader (that
    /// pins its height to the viewport and breaks vertical scrolling —
    /// 2026-08-13 fix, T063).
    private var paper: some View {
        // 004 T037: read the bridge state during body evaluation so
        // SwiftUI observes it (the insertion-control trigger).
        let textSelected = selectionBridge?.isTextSelected ?? false
        return VStack(alignment: .leading, spacing: BlockLayoutMetrics.documentSpacing) {
            // 004 T017 (FR-003): the editable title lives in the
            // paper, above the first content line (001 FR-050:
            // optional title; empty → nil).
            titleField

            // 004 修复 (2026-08-14, 文档顺序): ONE ordered block list — the
            // data order (host.blocks, canonical sortKey order) IS the
            // visual order. The former primary/secondary split pinned the
            // first rich-text block above every other block regardless of
            // its sortKey; every block now renders at its own position.
            // LazyVStack: FR-072b — only visible rows are realized for
            // notes with 100+ todo blocks (bounded row realization). The
            // stack spacing is the SINGLE inter-block rhythm source (004
            // 修复 2026-08-13 — block components own no vertical padding).
            LazyVStack(alignment: .leading, spacing: BlockLayoutMetrics.interBlockSpacing) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    BlockContainer {
                        blockView(block, index: index)
                    }
                }
            }
            // 004 T034 (FR-010): cursor-line hover triggers the insertion
            // control — hovering any block row counts.
            .onHover { hovering in
                isCursorLineHovered = hovering
            }
            // 004 修复 (2026-08-14, P0): the insertion control is an
            // ACCESSORY overlay, not a document-flow row — its visibility
            // never changes any block's frame (the control itself is
            // opacity-gated). It floats over the first block's leading
            // edge, transiently (cursor-line hover / selection), the
            // policy-sanctioned hover presentation (FR-043/CHK008).
            .overlay(alignment: .topLeading) {
                BlockInsertionControl(
                    onInsertTodo: onInsertTodo,
                    onInsertCode: onInsertCode,
                    onInsertFileReference: onInsertFileReference,
                    onCaptureScreenshot: onCaptureScreenshot,
                    isCursorLineHovered: $isCursorLineHovered,
                    isTextSelected: Binding(
                        get: { textSelected },
                        set: { _ in }
                    ),
                    isIMEComposing: $isIMEComposing
                )
            }

            // 004 修复 (2026-08-14, P0): the CLICKABLE tail Spacer. The
            // Spacer absorbs ALL remaining paper height (the document has
            // the viewport min-height above), and contentShape makes the
            // WHOLE absorbed region one hit target — clicking anywhere in
            // the empty paper below the last block continues the document.
            // A short document's entire tail is clickable; a long document
            // keeps only the min-height click surface after the last block.
            // In-flow: it never overlaps or steals clicks from any block.
            Spacer(minLength: BlockLayoutMetrics.continuationAreaMinHeight)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    onContinueDocument()
                }
                .accessibilityLabel(String(localized: "Continue writing"))
        }
    }

    // MARK: - 004 T058 title field (Q7 Apple Notes pattern, FR-003)

    /// The single visible title surface (Apple Notes pattern): the titlebar
    /// renders no title text (titleVisibility hidden); this in-content
    /// first line IS the title — editable, visually distinct from body
    /// text (bolder + larger; placeholder localizes via the catalog key
    /// `editor.titleField`).
    private var titleField: some View {
        TextField(String(localized: "editor.titleField", defaultValue: "Title"), text: Binding(
            get: { note.title ?? "" },
            set: { newValue in
                var updated = note
                updated.title = newValue.isEmpty ? nil : newValue
                onAppearanceChange(updated)
            }
        ))
        .textFieldStyle(.plain)
        .font(.title2.weight(.bold))
        .lineLimit(1)
        .truncationMode(.tail)
        .accessibilityLabel(String(localized: "Note Title"))
    }

    // MARK: - 004 T037 selection wiring (FR-010/FR-043)

    // MARK: - Block rendering

    @ViewBuilder
    private func blockView(_ block: Block, index: Int) -> some View {
        switch block.kind {
        case .richText:
            richTextBlockView(block, index: index)
        case .todo:
            TodoBlockView(
                block: block,
                textSize: ReadableTheme.textSize(for: note),
                onChanged: { updated in
                    // FR-141a: text edits debounce; completion/structural
                    // ops go through the repository directly (T290).
                    replaceBlock(updated, at: index)
                },
                todoProvider: todoProvider,
                onToggleComplete: onToggleTodo,
                onDelete: onDeleteTodo,
                onIndent: onIndentTodo,
                onOutdent: onOutdentTodo,
                onMove: onMoveTodo,
                selectionBridge: selectionBridge,
                undoManager: undoManager,
                requestFocus: pendingFocus?.blockId == block.id,
                caretAtEnd: pendingFocus?.position == .end,
                onFocusRequestHandled: handleFocusRequest,
                onFocusChange: { focused, hasMarkedText in
                    // FR-050a: an emptied todo merges away when the cursor
                    // exits it (FR-063 IME guard). The host owns the
                    // removal so the TodoItem row restores with the block.
                    guard !focused, !hasMarkedText else { return }
                    Task { await onEmptyTodoExit(block.id) }
                },
                todoRevision: todoRevision
            )
        case .code:
            CodeBlockView(
                block: block,
                onChanged: { updated in
                    replaceBlock(updated, at: index)
                },
                onDelete: onDeleteCode,
                selectionBridge: selectionBridge,
                undoManager: undoManager,
                requestFocus: pendingFocus?.blockId == block.id,
                caretAtEnd: pendingFocus?.position == .end,
                onFocusRequestHandled: handleFocusRequest,
                onFocusChange: { focused, hasMarkedText in
                    // FR-050a: an emptied code block merges away when the
                    // cursor exits it (FR-063 IME guard). Code carries no
                    // satellite rows — the view-level structural path
                    // (one undo group) is sufficient.
                    guard !focused, !hasMarkedText else { return }
                    guard let idx = blocks.firstIndex(where: { $0.id == block.id }),
                          let updated = EditorAppBridge.applyEmptyBlockRemoval(
                              blocks: blocks,
                              emptiedBlockIndex: idx,
                              hasIMEComposition: false
                          ) else { return }
                    onStructuralBlocksChanged(updated)
                }
            )
        case .fileRef:
            FileReferenceCardView(block: block, onAction: { action in
                Task { await onFileAction(block.id, action) }
            })
        case .screenshot:
            ScreenshotBlockView(block: block, onSetCover: { isCover in
                Task { await onSetCover(block.id, isCover) }
            }, onUpdateCaption: { caption in
                Task { await onUpdateCaption(block.id, caption) }
            }, onViewLarger: {
                onOpenViewer()
            })
        case .image:
            EmbeddedImageBlockView(block: block, onAction: { action in
                Task { await onEmbeddedImageAction(block.id, action) }
            })
        }
    }

    /// A rich-text block rendered at its sortKey position (004 修复
    /// 2026-08-14: the primary/secondary split is gone — every rich-text
    /// block is an editable block in the SAME editing context: bridge,
    /// undo manager, focus discipline). Styling is position-derived only:
    /// - the ONLY block keeps the 320pt empty-note click target;
    /// - a block with blocks below collapses its bottom inset (dead paper
    ///   under the last ink line);
    /// - the FIRST block keeps the 12pt top inset (first-line breathing
    ///   under the controls row); other blocks own none (the stack spacing
    ///   owns their rhythm).
    /// The OPENING paragraph (first rich-text block in sortKey order)
    /// keeps the primary commit path (FR-050 auto-link detection); the
    /// trailing blocks keep their plain commit — no behavior change.
    @ViewBuilder
    private func richTextBlockView(_ block: Block, index: Int) -> some View {
        if case .richText(let doc) = block.payload {
            let isOnlyBlock = blocks.count == 1
            let isFirstBlock = index == 0
            let hasBlocksBelow = index < blocks.count - 1
            let isOpeningParagraph = block.id == openingRichTextBlockId
            RichTextView(
                document: doc,
                textSize: ReadableTheme.textSize(for: note),
                onCommit: { document in
                    if isOpeningParagraph {
                        didRemoveEmptyBlockOnExit = false
                        commit(document)
                        let state = StickyLogger.editor.signpostBegin("editor.keystroke")
                        StickyLogger.editor.signpostEnd(state, op: "editor.keystroke")
                    } else {
                        replaceBlock(document, in: block)
                    }
                },
                onFocusChange: { focused, hasMarkedText in
                    // FR-063: the IME composition state drives every
                    // transformation/removal decision.
                    isIMEComposing = hasMarkedText
                    // T300 (FR-050a): when the cursor exits an emptied
                    // block, remove it — merge into the FOLLOWING block
                    // or delete outright (clarified 2026-08-07); the
                    // final block is never removed; suppressed while an
                    // IME composition is active (FR-063).
                    guard !focused, !hasMarkedText else { return }
                    // The opening paragraph's removal fires exactly once
                    // per exit; the flag resets on its next commit.
                    if isOpeningParagraph {
                        guard !didRemoveEmptyBlockOnExit else { return }
                        didRemoveEmptyBlockOnExit = true
                    }
                    guard let idx = blocks.firstIndex(where: { $0.id == block.id }),
                          let updated = EditorAppBridge.applyEmptyBlockRemoval(
                              blocks: blocks,
                              emptiedBlockIndex: idx,
                              hasIMEComposition: false
                          ) else { return }
                    // ONE undo group: the removal restores the block on
                    // a single Undo (FR-050a). Structural change persists
                    // immediately per FR-141a.
                    onStructuralBlocksChanged(updated)
                },
                selectionBridge: selectionBridge,
                richTextBlockId: block.id,
                undoManager: undoManager,
                minimumHeight: isOnlyBlock ? nil : 0,
                verticalInset: isFirstBlock ? RichTextView.textContainerVerticalInset : 0,
                collapsesBottomInset: hasBlocksBelow,
                requestFocus: pendingFocus?.blockId == block.id,
                caretAtEnd: pendingFocus?.position == .end,
                onFocusRequestHandled: handleFocusRequest
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// 004 修复: the new block's editor handled the insertion-focus
    /// request — clear the pending focus and report up (deferred to avoid
    /// mutating state during view update).
    private func handleFocusRequest() {
        DispatchQueue.main.async {
            pendingFocus = nil
            onFocusRequestHandled()
        }
    }

    /// Commits a trailing rich-text block edit (004 FR-010).
    private func replaceBlock(_ document: RichTextDocument, in block: Block) {
        var updated = blocks
        guard let idx = updated.firstIndex(where: { $0.id == block.id }) else { return }
        updated[idx] = Block(
            id: block.id,
            noteId: block.noteId,
            kind: .richText,
            sortKey: block.sortKey,
            payload: .richText(document),
            versionId: block.versionId,
            parentVersionId: block.parentVersionId,
            lastModifiedDeviceId: DeviceIdentity.current.id,
            createdAt: block.createdAt,
            modifiedAt: Date()
        )
        onBlocksChanged(updated)
    }

    // MARK: - Canonical ↔ AppKit bridging (T161; NSTextView fallback 2026-08-07)

    /// The opening rich-text paragraph (first rich-text block in sortKey
    /// order) — the former 004 "primary"'s ONLY surviving role: it owns
    /// the FR-050 auto-link commit path. It no longer changes rendering
    /// order (004 修复 2026-08-14).
    private var openingRichTextBlockId: UUID? {
        blocks.first(where: { $0.kind == .richText })?.id
    }

    /// Commits a canonical document produced by the opening paragraph:
    /// applies the FR-050 auto-link detection (T143) and persists through
    /// the host's debounced autosave (FR-141a).
    private func commit(_ document: RichTextDocument) {
        guard var richBlock = blocks.first(where: { $0.kind == .richText }) else {
            // Defensive (verified 2026-08-07): notes created before the
            // initial-block fix may lack the rich-text surface. Create it on
            // first commit so typed input is never dropped.
            let created = Block(
                noteId: note.id,
                kind: .richText,
                sortKey: 0,
                payload: .richText(document),
                lastModifiedDeviceId: DeviceIdentity.current.id
            )
            onStructuralBlocksChanged(blocks + [created])
            return
        }

        // FR-050 auto-link detection (T143): feed `link` marks.
        var doc = document
        let links = AutoLinkDetector.detectLinks(in: doc.text, insideCodeBlock: false)
        if !links.isEmpty {
            var paragraphs = doc.paragraphs
            for link in links {
                paragraphs = paragraphs.map { p in
                    var runs = p.runs
                    let intersecting = link.range.lowerBound < p.endScalar && link.range.upperBound > p.startScalar
                    if intersecting {
                        let start = max(link.range.lowerBound, p.startScalar)
                        let end = min(link.range.upperBound, p.endScalar)
                        runs.append(RichTextRun(startScalar: start, endScalar: end, marks: [], link: link.target))
                    }
                    return RichTextParagraph(startScalar: p.startScalar, endScalar: p.endScalar, style: p.style, runs: runs)
                }
            }
            doc = RichTextDocument(text: doc.text, paragraphs: paragraphs)
        }

        richBlock = Block(
            id: richBlock.id,
            noteId: richBlock.noteId,
            kind: .richText,
            sortKey: richBlock.sortKey,
            payload: .richText(doc),
            versionId: richBlock.versionId,
            parentVersionId: richBlock.parentVersionId,
            lastModifiedDeviceId: DeviceIdentity.current.id,
            createdAt: richBlock.createdAt,
            modifiedAt: Date()
        )
        replaceBlock(richBlock, at: blocks.firstIndex(where: { $0.id == richBlock.id }) ?? 0)
    }

    private func replaceBlock(_ block: Block, at index: Int, structural: Bool = false) {
        var updated = blocks
        let indices = blocks.indices.filter { blocks[$0].id == block.id }
        if let target = indices.first {
            updated[target] = block
        } else if blocks.indices.contains(index) {
            updated[index] = block
        }
        if structural {
            onStructuralBlocksChanged(updated)
        } else {
            onBlocksChanged(updated)
        }
    }
}

// MARK: - ContextualFormatBar (004 T039, FR-012/FR-013/FR-022/FR-029)

/// The floating glass format row: appears while text is selected (or a
/// format command is active), anchored over the editor, never stealing
/// focus (FR-012/FR-029). Buttons are standard SwiftUI controls inside a
/// single glass group (FR-022 — one grouped surface, not scattered
/// capsules). The only custom glass in the feature (plan §5.2).
struct ContextualFormatBar: View {
    @Bindable var bridge: EditorSelectionBridge

    var body: some View {
        // 004 修复: the row appears only for rich-text editors — plain-text
        // (code) editors accept no marks, so the row must not show there.
        if bridge.isTextSelected && bridge.hasFocus && bridge.richTextEditable {
            HStack(spacing: 2) {
                formatButton("bold", mark: .bold, help: String(localized: "Bold"))
                formatButton("italic", mark: .italic, help: String(localized: "Italic"))
                formatButton("underline", mark: .underline, help: String(localized: "Underline"))
                formatButton("strikethrough", mark: .strikethrough, help: String(localized: "Strikethrough"))
                formatButton("chevron.left.forwardslash.chevron.right", mark: .inlineCode, help: String(localized: "Code Style"))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(formatBarMaterial)
            .clipShape(Capsule())
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var formatBarMaterial: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(.regularMaterial)
                .glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(.regularMaterial)
        }
    }

    private func formatButton(_ systemImage: String, mark: RichTextMark, help: String) -> some View {
        Button {
            bridge.applyMarks([mark])
            // FR-029: the row never steals editing focus — restore the
            // editor as first responder after each action.
            bridge.textView?.window?.makeFirstResponder(bridge.textView)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
