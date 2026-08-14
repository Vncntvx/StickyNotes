import Testing
import Foundation
import AppKit
import Domain
import Persistence
import AssetStore
import SystemBridge
@testable import StickyNotes

// MARK: - Paragraph insertion tests (2026-08-14)
//
// 插入正文段落的两个入口：
// - todo 块尾 Return（无选中、无 Shift、非 IME）→ 在 todo 之后插入空正文
//   块并聚焦（Q5/Q6-B 决策）；中间 Return / Shift+Return / IME 组合 /
//   有选中 / code 块 → 保持默认换行（Q9-A/Q10-B）；
// - `+` 按钮菜单的"插入正文段落"→ 经 caret 上下文解析插入位置
//   （NoteWindowContent 接线，此处测 host 的 afterBlock 语义）。

@MainActor
@Suite struct ParagraphInsertionTests {

    // MARK: - Key routing (todo tail Return)

    private func makeTodoTextView(
        document: RichTextDocument,
        onInsertParagraphAfterSelf: @escaping () -> Void = {}
    ) -> (RichTextView.Coordinator, NotePaperTextView) {
        let editor = RichTextView(
            document: document,
            editorTypography: .system(textSize: 13),
            onCommit: { _ in },
            isSpecialBlock: true,
            onInsertParagraphAfterSelf: onInsertParagraphAfterSelf
        )
        let coordinator = RichTextView.Coordinator(editor)
        let textView = NotePaperTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))
        textView.isRichText = true
        textView.string = document.text
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.delegate = coordinator
        textView.blockKeyHandler = coordinator
        coordinator.attach(textView, bridge: nil, blockId: nil)
        return (coordinator, textView)
    }

    @Test
    func todoTailReturnInsertsParagraphAfterSelf() {
        var inserted = false
        let (_, textView) = makeTodoTextView(
            document: .plain("task"),
            onInsertParagraphAfterSelf: { inserted = true }
        )
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(inserted, "Return at the todo tail inserts a paragraph block (Q5-A)")
    }

    @Test
    func todoMidTextReturnKeepsNewline() {
        var inserted = false
        let (_, textView) = makeTodoTextView(
            document: .plain("task"),
            onInsertParagraphAfterSelf: { inserted = true }
        )
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(!inserted, "Return mid-todo stays a newline (Q9-A)")
    }

    @Test
    func todoTailShiftReturnKeepsNewline() {
        var inserted = false
        let (coordinator, textView) = makeTodoTextView(
            document: .plain("task"),
            onInsertParagraphAfterSelf: { inserted = true }
        )
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        #expect(!coordinator.handleInsertNewline(shift: true),
                "Shift+Return is an explicit newline, never a block insert (Q6-B)")
        #expect(!inserted)
    }

    @Test
    func imeCompositionSuppressesParagraphInsertion() {
        var inserted = false
        let (_, textView) = makeTodoTextView(
            document: .plain("task"),
            onInsertParagraphAfterSelf: { inserted = true }
        )
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.setMarkedText("拼", selectedRange: NSRange(location: 4, length: 1),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(!inserted, "Return during IME composition confirms the candidate (FR-063)")
    }

    @Test
    func todoSelectionReturnKeepsNewline() {
        var inserted = false
        let (_, textView) = makeTodoTextView(
            document: .plain("task"),
            onInsertParagraphAfterSelf: { inserted = true }
        )
        textView.setSelectedRange(NSRange(location: 1, length: 2))
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(!inserted, "a live selection is replaced by the newline, never a block insert")
    }

    @Test
    func richTextBlockTailReturnKeepsNewline() {
        // Only SPECIAL blocks (todo) intercept Return — the primary rich-text
        // block keeps its paragraph semantics.
        var inserted = false
        let editor = RichTextView(
            document: .plain("body"),
            editorTypography: .system(textSize: 13),
            onCommit: { _ in },
            onInsertParagraphAfterSelf: { inserted = true }
        )
        let coordinator = RichTextView.Coordinator(editor)
        #expect(!coordinator.handleInsertNewline(shift: false),
                "non-special blocks never intercept Return (Q9-A)")
        #expect(!inserted)
    }

    @Test
    func codeBlockTailReturnKeepsNewline() {
        // Q10-B: code blocks keep newline on Return — multi-line code is
        // frictionless; insertion goes through the `+` menu.
        let editor = CodeTextView(text: "let x = 1", onCommit: { _ in })
        let coordinator = CodeTextView.Coordinator(editor)
        #expect(!coordinator.handleInsertNewline(shift: false),
                "code blocks never intercept Return (Q10-B)")
    }

    // MARK: - Host insertion semantics (afterBlock)

    @Test
    func insertParagraphAfterTodoLandsBetweenBlocksAndFocusesIt() async throws {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let assetRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("paragraph-insert-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: assetRoot, withIntermediateDirectories: true)
        let assetStore = try AssetStore(directoryURL: assetRoot)
        let env = AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(directoryURL: assetRoot, store: assetStore),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.paragraph.\(UUID().uuidString)") ?? .standard)
        )
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed"); return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        guard let todoId = await host.insertTodoBlock() else {
            Issue.record("todo insert failed"); return
        }
        // A second todo AFTER the first: [rich, todo1, todo2].
        guard let secondTodoId = await host.insertTodoBlock() else {
            Issue.record("second todo insert failed"); return
        }
        await host.flush()
        let before = host.blocks

        let newId = await host.insertRichTextBlock(target: .afterBlock(blockId: todoId))

        let newIdValue = try #require(newId)
        #expect(host.blocks.count == before.count + 1)
        let inserted = host.blocks
        #expect(inserted[1].id == todoId, "the first todo stays in place")
        #expect(inserted[2].id == newIdValue, "the paragraph lands BETWEEN the two todos")
        #expect(inserted[3].id == secondTodoId, "the second todo follows")
        guard case .richText(let doc) = inserted[2].payload else {
            Issue.record("expected a rich-text payload"); return
        }
        #expect(doc.text.isEmpty, "the inserted paragraph starts empty")
        #expect(host.pendingFocusRequest?.blockId == newIdValue,
                "the new paragraph takes focus")
        #expect(host.pendingFocusRequest?.position == .start)

        // Undo removes the inserted paragraph in one group.
        host.undoManager.undo()
        let deadline = ContinuousClock.now + .seconds(4)
        while host.blocks.contains(where: { $0.id == newIdValue }) {
            if ContinuousClock.now >= deadline {
                Issue.record("undo must remove the inserted paragraph")
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(host.blocks.count == before.count)
    }
}
