import SwiftUI
import AppKit
import Domain
import EditorCore
import Persistence
import SystemBridge

// MARK: - RichTextBlockView (T161/T211/T259)
//
// Per tasks.md T161/T211/T259 and spec FR-050/FR-051/FR-052/FR-053/FR-054/
// FR-060/FR-061/FR-062/FR-063:
// - SwiftUI `TextEditor` + `AttributedString` rich-text block.
// - The canonical rich-text document is the source of truth; the view
//   bridges to SwiftUI attributed state via `RichTextAdapter` (T161) and
//   back (only supported marks survive — FR-053).
// - Markdown transforms fire IME-safely (FR-063); keystroke path is
//   signpost-bracketed (SC-004a, T211); auto-link detection feeds the
//   `link` mark (FR-050, T143).
// - Cross-block selection semantics (FR-054) are provided by
//   `CrossBlockSelectionCore`; the empty-block removal rule (FR-050a) by
//   `BlockMergeOperation`.

/// The rich-text block editor (one note = one seamless rich-text block
/// surface per note window; special blocks are rendered around it by the
/// host).
public struct RichTextBlockView: View {
    let note: Note
    let blocks: [Block]
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

    @State private var attributedText = AttributedString("")
    @State private var isIMEComposing = false
    // T300 (FR-050a): cursor-exit detection for empty-block removal. The
    // decision fires exactly once per exit; the flag resets when the block
    // gains non-empty text again.
    @FocusState private var editorFocused: Bool
    @State private var didRemoveEmptyBlockOnExit = false

    public init(
        note: Note,
        blocks: [Block],
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
            VStack(alignment: .leading, spacing: 10) {
                // Rich-text block (the seamless primary surface).
                TextEditor(text: $attributedText)
                    .font(.system(size: ReadableTheme.textSize(for: note)))
                    .foregroundStyle(ReadableTheme.foreground(for: note))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .focused($editorFocused)
                    .onAppear {
                        syncFromCanonical()
                    }
                    .onChange(of: attributedText) { _, newValue in
                        // T211: signpost-bracket the keystroke path
                        // (SC-004a); sanitized op name only.
                        let state = StickyLogger.editor.signpostBegin("editor.keystroke")
                        didRemoveEmptyBlockOnExit = false
                        commit(newValue)
                        StickyLogger.editor.signpostEnd(state, op: "editor.keystroke")
                    }
                    .onChange(of: editorFocused) { _, focused in
                        // T300 (FR-050a): when the cursor exits an emptied
                        // block, remove it — merge into the FOLLOWING block
                        // or delete outright (clarified 2026-08-07); the
                        // final block is never removed; suppressed while an
                        // IME composition is active (FR-063).
                        guard !focused, !isIMEComposing, !didRemoveEmptyBlockOnExit else { return }
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
                    }

                // FR-050 block insertion (T290): todos, code blocks, file
                // references (Finder drag-drop handled at the window level).
                HStack(spacing: 10) {
                    Menu {
                        Button("Add Todo", action: onInsertTodo)
                            .keyboardShortcut("t", modifiers: [.command, .shift])
                        Button("Add Code Block", action: onInsertCode)
                            .keyboardShortcut("c", modifiers: [.command, .shift])
                        Divider()
                        Button("Add File Reference…", action: onInsertFileReference)
                        Button("Capture Screenshot…", action: onCaptureScreenshot)
                    } label: {
                        Label("Add Block", systemImage: "plus.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Add block")

                    Spacer()
                }
                .padding(.bottom, 2)

                // Special blocks rendered beneath (todo/code/file/image/
                // screenshot) with the unified container (FR-050b).
                // LazyVStack: FR-072b — only visible rows are realized for
                // notes with 100+ todo blocks (bounded row realization).
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(specialBlocks.enumerated()), id: \.element.id) { index, block in
                        BlockContainer {
                            blockView(block, index: index)
                        }
                    }
                }
            }
            .padding(10)
        }
    }

    // MARK: - Block rendering

    private var specialBlocks: [Block] {
        blocks.filter { $0.kind != .richText }
    }

    @ViewBuilder
    private func blockView(_ block: Block, index: Int) -> some View {
        switch block.kind {
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
        case .richText:
            EmptyView()
        }
    }

    // MARK: - Canonical ↔ SwiftUI bridging (T161)

    /// Loads the first rich-text block's canonical document into the
    /// SwiftUI attributed string (only supported marks — FR-053).
    private func syncFromCanonical() {
        guard let richBlock = blocks.first(where: { $0.kind == .richText }),
              case .richText(let doc) = richBlock.payload else {
            attributedText = AttributedString("")
            return
        }
        var attributed = AttributedString(doc.text)
        for paragraph in doc.paragraphs {
            for run in paragraph.runs {
                let start = attributed.index(attributed.startIndex, offsetByCharacters: run.startScalar)
                let end = attributed.index(attributed.startIndex, offsetByCharacters: run.endScalar)
                guard start < end else { continue }
                let range = start..<end
                if run.marks.contains(.bold) { attributed[range].inlinePresentationIntent = .stronglyEmphasized }
                if run.marks.contains(.italic) { attributed[range].inlinePresentationIntent = .emphasized }
                if run.marks.contains(.strikethrough) { attributed[range].strikethroughStyle = .single }
                if run.marks.contains(.underline) { attributed[range].underlineStyle = .single }
                if run.marks.contains(.inlineCode) {
                    attributed[range].font = Font.system(.body, design: .monospaced)
                }
                if let link = run.link {
                    attributed[range].link = URL(string: link)
                }
            }
        }
        attributedText = attributed
    }

    /// Commits the SwiftUI attributed state back to the canonical document
    /// (strip unsupported attributes; IME-safe; auto-link detection).
    private func commit(_ newValue: AttributedString) {
        // IME marked text: keep the raw state, do not transform (FR-063).
        if isIMEComposing { return }
        guard var richBlock = blocks.first(where: { $0.kind == .richText }) else { return }

        let plainText = String(newValue.characters)
        var doc = RichTextAdapter.document(fromPlainText: plainText)

        // Rebuild runs from the supported attributes (FR-053).
        var runs: [RichTextRun] = []
        var cursor = 0
        let scalars = Array(doc.text.unicodeScalars)
        for run in newValue.runs {
            let subText = String(newValue[run.range].characters)
            let runLength = subText.unicodeScalars.count
            let start = max(0, cursor)
            let end = min(scalars.count, cursor + runLength)
            cursor = end
            guard end > start else { continue }
            var marks: Set<RichTextMark> = []
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { marks.insert(.bold) }
                if intent.contains(.emphasized) { marks.insert(.italic) }
            }
            if run.strikethroughStyle != nil { marks.insert(.strikethrough) }
            if run.underlineStyle != nil { marks.insert(.underline) }
            runs.append(RichTextRun(startScalar: start, endScalar: end, marks: marks))
        }
        if let last = runs.last, last.endScalar < scalars.count {
            runs.append(RichTextRun(startScalar: last.endScalar, endScalar: scalars.count, marks: []))
        }
        doc = RichTextDocument(
            text: doc.text,
            paragraphs: doc.paragraphs.isEmpty ? [RichTextParagraph(startScalar: 0, endScalar: scalars.count, style: .body, runs: runs)] : doc.paragraphs.map { p in
                RichTextParagraph(startScalar: p.startScalar, endScalar: p.endScalar, style: p.style, runs: p.runs.isEmpty ? runs.filter { $0.startScalar >= p.startScalar && $0.endScalar <= p.endScalar } : p.runs)
            }
        )

        // FR-050 auto-link detection (T143): feed `link` marks.
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
