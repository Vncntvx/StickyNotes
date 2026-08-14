import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
import Persistence
import AssetStore
@testable import StickyNotes

// MARK: - Editor block-editing tests (T290, US4)
//
// Per tasks.md T290: the block-editing surface — insert todo/code/file
// blocks, TodoRepository-backed completion (FR-070/FR-071), reorder/
// indent/outdent (FR-072a), delete, and Finder-drag file references
// (FR-100). The pre-Phase-27 toggle flipped local `@State` only.

@MainActor
@Suite struct EditorBlockEditingTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000010")!

    private func makeEnvironment(assetRoot: URL? = nil) throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        var assetStore: AssetStore?
        if let assetRoot {
            assetStore = try AssetStore(directoryURL: assetRoot)
        }
        return AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(directoryURL: assetRoot, store: assetStore),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.blocks.\(UUID().uuidString)") ?? .standard)
        )
    }

    // MARK: - 004 T061 (SC-004): title and body share one left edge

    @Test
    func bodyTextLeftOriginAlignsWithTitleField() {
        #expect(RichTextView.textContainerHorizontalInset == 0,
                "body text-container horizontal inset must be 0 — title and body share one left edge (2026-08-13 feedback)")
        #expect(RichTextView.lineFragmentPadding == 0,
                "body line-fragment padding must be 0 — no stray offset vs the title line")
    }

    @Test
    func bodyVerticalBreathingRoomPreserved() {
        // 004 T062 (2026-08-13): vertical inset compressed 16→12 as part of
        // the title→body gap reduction (~-26% total) — sticky-note feel,
        // not an article editor.
        #expect(RichTextView.textContainerVerticalInset == 12,
                "vertical inset keeps first-line breathing without an editor-like gap")
    }

    // MARK: - 004 T063: the paper grows with content (scroll precondition)

    @Test
    func notePaperTextViewIntrinsicHeightGrowsWithLongContent() {
        let textView = NotePaperTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 320))
        textView.string = String(repeating: "scrolling line\n", count: 200)
        // No manual ensureLayout — the intrinsic size itself must reflect
        // the full document (T063: ensureLayout inside intrinsicContentSize
        // + didChangeText invalidation), otherwise the enclosing SwiftUI
        // ScrollView never scrolls a long note.
        let tall = textView.intrinsicContentSize.height
        #expect(tall > NotePaperTextView.minimumPaperHeight,
                "long content must grow the paper beyond the minimum — scroll precondition")
        #expect(tall > 600,
                "200 lines must produce a tall paper (actual \(tall))")
    }

    @Test
    func insertTodoTogglePersistsCompletion() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()

        // Insert a todo block (stable TodoItem identity — FR-071).
        guard let blockId = await host.insertTodoBlock() else {
            Issue.record("insertTodoBlock failed")
            return
        }
        let item = await host.todoItem(forBlock: blockId)
        #expect(item != nil, "the todo has a backing TodoItem (FR-071)")

        // Toggle complete → persisted through the repository.
        await host.setTodoComplete(blockId: blockId, isComplete: true)
        let reloaded = NoteWindowHostModel(noteId: noteId, environment: env)
        await reloaded.load()
        let fetched = await reloaded.todoItem(forBlock: blockId)
        #expect(fetched?.isComplete == true, "completion persists via TodoRepository (FR-070)")

        // A second toggle back.
        await reloaded.setTodoComplete(blockId: blockId, isComplete: false)
        let again = await reloaded.todoItem(forBlock: blockId)
        #expect(again?.isComplete == false)
    }

    @Test
    func insertCodeBlockPersists() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        guard let blockId = await host.insertCodeBlock() else {
            Issue.record("insertCodeBlock failed")
            return
        }
        let fetched = try await env.persistence.noteRepository!.fetchBlocks(noteId: noteId)
        #expect(fetched.contains { $0.id == blockId && $0.kind == .code }, "code block persisted (FR-080)")
    }

    @Test
    func insertFileReferencePersistsBlockAndLocator() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()

        // A temp file as the referenced file; bookmark creation injected
        // (sandbox-independent; the real bridge is covered by T163e).
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ref-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        guard let blockId = await host.insertFileReferenceBlock(
            url: fileURL,
            bookmarkCreator: { _ in Data("fake-bookmark".utf8) }
        ) else {
            Issue.record("insertFileReferenceBlock failed")
            return
        }
        let blocks = try await env.persistence.noteRepository!.fetchBlocks(noteId: noteId)
        guard let block = blocks.first(where: { $0.id == blockId }) else {
            Issue.record("file-reference block missing")
            return
        }
        if case .fileReference(let ref) = block.payload {
            #expect(ref.displayName == fileURL.lastPathComponent, "generic metadata persisted (FR-100/FR-105)")
            #expect(ref.approximateSize == 5)
        } else {
            Issue.record("expected a fileReference payload")
        }
        let locator = try await env.persistence.fileLocatorRepository!.fetch(blockId: blockId)
        #expect(locator != nil, "device-local bookmark persisted (FR-105)")
        #expect(locator?.lastResolvedPath == fileURL.path)
    }

    @Test
    func deleteTodoRemovesBlockAndItem() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        guard let blockId = await host.insertTodoBlock() else {
            Issue.record("insertTodoBlock failed")
            return
        }
        await host.deleteTodo(blockId: blockId)
        let blocks = try await env.persistence.noteRepository!.fetchBlocks(noteId: noteId)
        #expect(!blocks.contains { $0.id == blockId }, "todo block removed")
        let item = await host.todoItem(forBlock: blockId)
        #expect(item == nil, "backing TodoItem removed")
    }

    // MARK: - 统一编辑上下文（004 修复：尾部块布局 / todo 富文本 / code 可编辑）

    @Test
    func trailingRichTextEditorIsContentSized() {
        // 尾部 richText 编辑器（caret split 的第二半）内容自适应——不再
        // 渲染为第二张 320pt 纸面（插入后的布局断裂修复）。
        let trailing = NotePaperTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        trailing.minimumHeight = 0
        trailing.string = "short tail"
        let compact = trailing.intrinsicContentSize.height
        #expect(compact < 100, "trailing editors must size to content, not the paper minimum (got \(compact))")
        #expect(compact >= trailing.textContainerInset.height * 2, "the inset still contributes")

        // 主纸面保持 320 最小高度（窗口填充/点击面）。
        let primary = NotePaperTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 320))
        #expect(primary.intrinsicContentSize.height >= NotePaperTextView.minimumPaperHeight,
                "the primary paper keeps the 320 minimum")
    }

    @Test
    func todoEditorRoundTripsRunMarks() throws {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        let primary = Block(
            noteId: note.id, kind: .richText, sortKey: 0,
            payload: .richText(.plain("head")), lastModifiedDeviceId: Self.deviceId
        )
        let todoBlock = Block(
            noteId: note.id, kind: .todo, sortKey: 1024,
            payload: .todo(TodoPayload(todoId: UUID(), richText: RichTextDocument(
                text: "buy milk",
                paragraphs: [RichTextParagraph(startScalar: 0, endScalar: 8, style: .body, runs: [
                    RichTextRun(startScalar: 0, endScalar: 3, marks: [.bold])
                ])]
            ))),
            lastModifiedDeviceId: Self.deviceId
        )
        var committed: [Block] = []
        let hosting = NSHostingView(rootView: RichTextBlockView(
            note: note, editorTypography: .system(textSize: CGFloat(note.textSize)), blocks: [primary, todoBlock], onBlocksChanged: { committed = $0 }
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 800)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let editors = allTextViews(in: hosting)
        let todoEditor = try #require(editors.first { $0.string == "buy milk" },
                                      "the todo row must be hosted by a rich-text editor")
        // 模型 → 视图：bold run 呈现。
        let font = todoEditor.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true,
                "todo text must render its run marks (FR-053)")

        // 视图 → 模型：textDidChange 提交保留 marks。
        todoEditor.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: todoEditor))
        guard let updated = committed.first(where: { $0.id == todoBlock.id }),
              case .todo(let payload) = updated.payload else {
            Issue.record("todo commit must reach onBlocksChanged")
            return
        }
        #expect(payload.richText.text == "buy milk")
        #expect(payload.richText.paragraphs.flatMap(\.runs).contains { $0.marks.contains(.bold) },
                "todo text edits must preserve run marks (FR-053)")
    }

    @Test
    func codeEditorCommitsPlainTextIntoPayload() throws {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        let primary = Block(
            noteId: note.id, kind: .richText, sortKey: 0,
            payload: .richText(.plain("head")), lastModifiedDeviceId: Self.deviceId
        )
        let codeBlock = Block(
            noteId: note.id, kind: .code, sortKey: 1024,
            payload: .code(CodePayload(text: "", language: nil)),
            lastModifiedDeviceId: Self.deviceId
        )
        var committed: [Block] = []
        let hosting = NSHostingView(rootView: RichTextBlockView(
            note: note, editorTypography: .system(textSize: CGFloat(note.textSize)), blocks: [primary, codeBlock], onBlocksChanged: { committed = $0 }
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 800)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let editors = allTextViews(in: hosting)
        let codeEditor = try #require(editors.first { !$0.isRichText },
                                      "the code block must be hosted by a plain-text editor")
        codeEditor.string = "let x = 1\n"
        // 明确触发 textDidChange（离屏无 first responder 时程序化 string
        // 赋值不保证派发通知；提交幂等，双重触发无害）。
        codeEditor.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: codeEditor))

        guard let updated = committed.first(where: { $0.id == codeBlock.id }),
              case .code(let payload) = updated.payload else {
            Issue.record("code commit must reach onBlocksChanged")
            return
        }
        #expect(payload.text == "let x = 1\n", "code editing must write CodePayload.text")
        #expect(payload.language == nil, "the language field must be preserved")
    }

    // MARK: - Shared helpers

    private func allTextViews(in view: NSView) -> [NSTextView] {
        var result: [NSTextView] = []
        if let textView = view as? NSTextView { result.append(textView) }
        for subview in view.subviews {
            result.append(contentsOf: allTextViews(in: subview))
        }
        return result
    }

    @Test
    func reorderAndIndentPersist() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        guard let first = await host.insertTodoBlock(), let second = await host.insertTodoBlock() else {
            Issue.record("insert failed")
            return
        }
        // Indent the second under the first (FR-072a depth bound enforced
        // by the repository).
        await host.indentTodo(blockId: second)
        let all = await host.todos()
        let secondItem = all.first { $0.blockId == second }
        #expect(secondItem?.parentTodoId == all.first { $0.blockId == first }?.id, "indent reparents (FR-070)")

        // Outdent back.
        await host.outdentTodo(blockId: second)
        let afterOutdent = await host.todos().first { $0.blockId == second }
        #expect(afterOutdent?.parentTodoId == nil, "outdent restores top level")
    }
}
