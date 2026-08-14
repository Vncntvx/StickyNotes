import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
import EditorCore
import Persistence
@testable import StickyNotes

// MARK: - Unified editing infrastructure (004 修复, 2026-08-13)
//
// Todo/Code Block 插入后必须保持同一文档编辑上下文（新 FR）：
// - 每窗口一个共享 UndoManager：所有块编辑器（正文/todo/code）共用；
// - 结构变更（插入/删除/移动/勾选）= 单个撤销组，⌘Z 恢复插入前文档、
//   ⌘⇧Z 重放；结构变更清空此前的逐字输入撤销（已确认决策）；
// - 插入完成后 First Responder 移入新块（光标在内容开头）。

@MainActor
@Suite struct UnifiedEditingInfrastructureTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000040")!

    // MARK: - Environment

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(directoryURL: nil, store: nil),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.unified.\(UUID().uuidString)") ?? .standard)
        )
    }

    private func makeHost() async throws -> NoteWindowHostModel {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            throw TestFailure.blankNoteFailed
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        return host
    }

    private enum TestFailure: Error {
        case blankNoteFailed
        case insertFailed
    }

    // MARK: - Helpers

    private func allTextViews(in view: NSView) -> [NSTextView] {
        var result: [NSTextView] = []
        if let textView = view as? NSTextView { result.append(textView) }
        for subview in view.subviews {
            result.append(contentsOf: allTextViews(in: subview))
        }
        return result
    }

    private func makeHosting(
        note: Note,
        blocks: [Block],
        undoManager: UndoManager? = nil,
        focusRequest: EditorFocusRequest? = nil,
        onFocusRequestHandled: @escaping () -> Void = {},
        onBlocksChanged: @escaping ([Block]) -> Void = { _ in }
    ) -> NSHostingView<RichTextBlockView> {
        let hosting = NSHostingView(rootView: RichTextBlockView(
            note: note,
            editorTypography: .system(textSize: CGFloat(note.textSize)),
            blocks: blocks,
            onBlocksChanged: onBlocksChanged,
            undoManager: undoManager,
            focusRequest: focusRequest,
            onFocusRequestHandled: onFocusRequestHandled
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 800)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        return hosting
    }

    /// Polls until `condition` is true (undo effects are async — the
    /// restore closures run through the host's serialized undo queue).
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("condition not met within \(timeout)")
    }

    // MARK: - Shared undo manager

    @Test
    func allEditorsInOneWindowShareOneUndoManager() throws {
        let shared = UndoManager()
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        let primary = Block(
            noteId: note.id, kind: .richText, sortKey: 0,
            payload: .richText(.plain("head")), lastModifiedDeviceId: Self.deviceId
        )
        let todo = Block(
            noteId: note.id, kind: .todo, sortKey: 1024,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("buy milk"))),
            lastModifiedDeviceId: Self.deviceId
        )
        let trailing = Block(
            noteId: note.id, kind: .richText, sortKey: 2048,
            payload: .richText(.plain("tail")), lastModifiedDeviceId: Self.deviceId
        )
        let hosting = makeHosting(note: note, blocks: [primary, todo, trailing], undoManager: shared)
        let editors = allTextViews(in: hosting)
        #expect(editors.count >= 3, "primary/todo/trailing editors must all instantiate (got \(editors.count))")
        for editor in editors {
            #expect(editor.undoManager === shared, "every block editor must share the window-level UndoManager")
        }
    }

    // MARK: - Structural undo groups

    @Test
    func insertTodoBlockRegistersOneUndoGroup() async throws {
        let host = try await makeHost()
        guard let blockId = await host.insertTodoBlock() else {
            Issue.record("insertTodoBlock failed")
            return
        }
        #expect(host.undoManager.canUndo, "insertion must register an undo group")
        let afterInsert = host.blocks

        host.undoManager.undo()
        try await waitUntil {
            !host.blocks.contains { $0.id == blockId }
        }
        try await waitUntil {
            await host.todoItem(forBlock: blockId) == nil
        }
        #expect(host.blocks != afterInsert, "undo must restore the pre-insert block list")
        try await waitUntil {
            await host.todoItem(forBlock: blockId) == nil
        }
        #expect(await host.todoItem(forBlock: blockId) == nil, "undo must remove the orphaned TodoItem row")

        #expect(host.undoManager.canRedo, "undo must register the inverse for redo")
        host.undoManager.redo()
        try await waitUntil {
            host.blocks.contains { $0.id == blockId }
        }
        try await waitUntil {
            await host.todoItem(forBlock: blockId) != nil
        }
        #expect(await host.todoItem(forBlock: blockId) != nil, "redo must re-insert the TodoItem")
    }

    @Test
    func caretSplitInsertionUndoRestoresSingleBlock() async throws {
        let host = try await makeHost()
        let richId = UUID()
        let doc = RichTextDocument.plain("hello world")
        let rich = Block(
            id: richId,
            noteId: host.noteId, kind: .richText, sortKey: 0,
            payload: .richText(doc), lastModifiedDeviceId: Self.deviceId
        )
        host.updateBlocks([rich], isStructural: true)
        await host.flush()

        guard await host.insertTodoBlock(target: .caretSplit(blockId: richId, offset: 5)) != nil else {
            Issue.record("insertTodoBlock failed")
            return
        }
        #expect(host.blocks.count == 3, "caretSplit must produce leading + todo + trailing")
        #expect(host.blocks.contains { $0.kind == .todo })

        host.undoManager.undo()
        try await waitUntil {
            host.blocks.count == 1
        }
        #expect(host.blocks.first?.id == richId, "undo must restore the original single block")
        #expect(host.blocks.first?.payload == .richText(doc),
                "undo must merge leading+trailing back into the original document")
    }

    @Test
    func structuralChangesPreserveFullUndoHistory() async throws {
        let host = try await makeHost()
        guard let first = await host.insertTodoBlock() else {
            Issue.record("first insert failed")
            return
        }
        guard let second = await host.insertTodoBlock() else {
            Issue.record("second insert failed")
            return
        }
        #expect(host.blocks.filter { $0.kind == .todo }.count == 2)

        // 修订（2026-08-13 用户实测）：结构变更 MUST NOT 清空历史——
        // 撤销第二个插入不得顺带清掉第一个插入的撤销组。
        host.undoManager.undo()
        try await waitUntil {
            !host.blocks.contains { $0.id == second }
        }
        #expect(host.blocks.contains { $0.id == first },
                "undoing the 2nd insert must preserve the 1st (no removeAllActions)")
        host.undoManager.undo()
        try await waitUntil {
            !host.blocks.contains { $0.id == first }
        }
        #expect(!host.blocks.contains { $0.kind == .todo }, "both inserts undone")
        #expect(!host.undoManager.canUndo, "the undo stack is fully consumed")
    }

    @Test
    func insertedBlockReceivesFirstResponderFocus() async throws {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        let primary = Block(
            noteId: note.id, kind: .richText, sortKey: 0,
            payload: .richText(.plain("head")), lastModifiedDeviceId: Self.deviceId
        )
        let todoId = UUID()
        let todo = Block(
            id: todoId, noteId: note.id, kind: .todo, sortKey: 1024,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .plain(""))),
            lastModifiedDeviceId: Self.deviceId
        )
        var handled = false
        let hosting = NSHostingView(rootView: RichTextBlockView(
            note: note,
            editorTypography: .system(textSize: CGFloat(note.textSize)),
            blocks: [primary, todo],
            onBlocksChanged: { _ in },
            focusRequest: EditorFocusRequest(blockId: todoId, position: .start),
            onFocusRequestHandled: { handled = true }
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let editors = allTextViews(in: hosting)
        let todoEditor = try #require(editors.first { $0.string.isEmpty }, "the inserted todo block must render its editor")
        // The focus request retries on the runloop until the window
        // attaches — poll with awaits so the main actor processes the hops.
        for _ in 0..<100 {
            if handled { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(handled, "the focus request must be reported as handled")
        #expect(window.firstResponder === todoEditor, "the inserted block's editor must become first responder")
        window.close()
    }
}
