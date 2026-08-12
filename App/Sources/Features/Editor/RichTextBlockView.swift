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
    let onFileAction: (UUID, FileReferenceAction) async -> Void
    let onSetCover: (UUID?, Bool) async -> Void
    let onUpdateCaption: (UUID, String?) async -> Void
    let onOpenViewer: () -> Void
    let onEmbeddedImageAction: (UUID, EmbeddedImageAction) async -> Void

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
        onFileAction: @escaping (UUID, FileReferenceAction) async -> Void = { _, _ in },
        onSetCover: @escaping (UUID?, Bool) async -> Void = { _, _ in },
        onUpdateCaption: @escaping (UUID, String?) async -> Void = { _, _ in },
        onOpenViewer: @escaping () -> Void = {},
        onEmbeddedImageAction: @escaping (UUID, EmbeddedImageAction) async -> Void = { _, _ in }
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
        self.onFileAction = onFileAction
        self.onSetCover = onSetCover
        self.onUpdateCaption = onUpdateCaption
        self.onOpenViewer = onOpenViewer
        self.onEmbeddedImageAction = onEmbeddedImageAction
    }

    public var body: some View {
        ScrollView {
            // 004 T042 (FR-019): the ONLY custom width-aware rule — two
            // semantic content insets (compact 10pt / regular 14–16pt,
            // switching at 480pt; capped at 24pt so wide windows never
            // center the text into a document column). NSToolbar cannot
            // express content insets, so this stays the single exception
            // (plan §5/§8).
            GeometryReader { proxy in
                // 004 T037: read the bridge state during body evaluation so
                // SwiftUI observes it (the insertion-control trigger).
                let textSelected = selectionBridge?.isTextSelected ?? false
                let compact = proxy.size.width < 480
                let inset: CGFloat = compact ? 10 : min(14 + (proxy.size.width - 480) / 240, 24)
                VStack(alignment: .leading, spacing: 8) {
                    // 004 T017 (FR-003): the editable title lives in the
                    // paper, above the first content line (001 FR-050:
                    // optional title; empty → nil).
                    titleField

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

                    // Rich-text block (the seamless primary surface) —
                    // NSTextView-backed (verified 2026-08-07: SwiftUI
                    // `TextEditor`'s binding never writes back on macOS 27
                    // beta; plan-sanctioned fallback, canonical format
                    // unchanged). Natural height so short notes fit without
                    // a scroll track.
                    primaryEditor

                    // Special blocks rendered beneath (todo/code/file/image/
                    // screenshot) with the unified container (FR-050b).
                    // LazyVStack: FR-072b — only visible rows are realized
                    // for notes with 100+ todo blocks (bounded row
                    // realization). 004 FR-010: trailing rich-text blocks
                    // (caret splits) render as editable blocks too.
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(secondaryBlocks.enumerated()), id: \.element.id) { index, block in
                            BlockContainer {
                                blockView(block, index: index)
                            }
                        }
                    }
                }
                .padding(.horizontal, inset)
                .padding(.bottom, 10)
                .padding(.top, 8)
            }
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

    // MARK: - Editor surfaces

    /// The primary seamless rich-text surface (first rich-text block).
    private var primaryEditor: some View {
        RichTextView(
            document: canonicalDocument,
            textSize: ReadableTheme.textSize(for: note),
            onCommit: { document in
                didRemoveEmptyBlockOnExit = false
                commit(document)
                let state = StickyLogger.editor.signpostBegin("editor.keystroke")
                StickyLogger.editor.signpostEnd(state, op: "editor.keystroke")
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
                guard !focused, !hasMarkedText, !didRemoveEmptyBlockOnExit else { return }
                didRemoveEmptyBlockOnExit = true
                guard let richIndex = blocks.firstIndex(where: { $0.kind == .richText }),
                      let updated = EditorAppBridge.applyEmptyBlockRemoval(
                          blocks: blocks,
                          emptiedBlockIndex: richIndex,
                          hasIMEComposition: false
                      ) else { return }
                // ONE undo group: the removal restores the block on
                // a single Undo (FR-050a). Structural change persists
                // immediately per FR-141a.
                onStructuralBlocksChanged(updated)
            },
            selectionBridge: selectionBridge,
            richTextBlockId: primaryRichTextBlock?.id
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // 004 T034 (FR-010): cursor-line hover triggers the insertion
        // control.
        .onHover { hovering in
            isCursorLineHovered = hovering
        }
    }

    // MARK: - Block rendering

    /// All non-primary blocks: special blocks + trailing rich-text blocks
    /// (caret splits — 004 FR-010).
    private var secondaryBlocks: [Block] {
        guard let primaryId = primaryRichTextBlock?.id else { return blocks }
        return blocks.filter { $0.id != primaryId }
    }

    @ViewBuilder
    private func blockView(_ block: Block, index: Int) -> some View {
        switch block.kind {
        case .richText:
            // 004 FR-010: a trailing rich-text block (the caret split's
            // second half) is editable like the primary surface.
            if case .richText(let doc) = block.payload {
                RichTextView(
                    document: doc,
                    textSize: ReadableTheme.textSize(for: note),
                    onCommit: { document in
                        replaceBlock(document, in: block)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .todo:
            TodoBlockView(
                block: block,
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
                onMove: onMoveTodo
            )
        case .code:
            CodeBlockView(block: block)
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

    /// The primary rich-text block (the editor's main surface).
    private var primaryRichTextBlock: Block? {
        blocks.first(where: { $0.kind == .richText })
    }

    /// The canonical document backing the editor (the model owns it; the
    /// representable mirrors it).
    private var canonicalDocument: RichTextDocument {
        guard let richBlock = primaryRichTextBlock,
              case .richText(let doc) = richBlock.payload else {
            return .empty
        }
        return doc
    }

    /// Commits a canonical document produced by the editor: applies the
    /// FR-050 auto-link detection (T143) and persists through the host's
    /// debounced autosave (FR-141a).
    private func commit(_ document: RichTextDocument) {
        guard var richBlock = primaryRichTextBlock else {
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
        if bridge.isTextSelected && bridge.hasFocus {
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
