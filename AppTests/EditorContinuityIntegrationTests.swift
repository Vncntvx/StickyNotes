import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
import EditorCore
import Persistence
import SystemBridge
@testable import StickyNotes

// MARK: - Editor continuity integration (004 修复, 2026-08-13 回归)
//
// 用户实测回归（2026-08-13）：headless 单测全绿但真实 App 中症状依旧。
// 根因之一：`makeCoordinator` 只在首次渲染捕获 `parent` struct——真实 App
// 中 caret-split 插入后，主编辑器再打一个字就用插入前的旧 `blocks` 快照
// 提交，把刚插入的 Todo/尾部块整体抹掉（编辑上下文断裂、⌘Z 无法恢复）。
// 本套件走真实 NoteWindowContent → RichTextBlockView → NSTextView 管线，
// 复现"插入后继续打字"场景并钉住不回归。

@MainActor
@Suite struct EditorContinuityIntegrationTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000050")!

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
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.continuity.\(UUID().uuidString)") ?? .standard)
        )
    }

    private func allTextViews(in view: NSView) -> [NSTextView] {
        var result: [NSTextView] = []
        if let textView = view as? NSTextView { result.append(textView) }
        for subview in view.subviews {
            result.append(contentsOf: allTextViews(in: subview))
        }
        return result
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("condition not met within \(timeout)")
    }

    @Test
    func typingAfterCaretSplitInsertionKeepsInsertedBlocks() async throws {
        let env = try makeEnvironment()
        let coordinator = NoteWindowCoordinator(environment: env)
        let repo = try #require(env.persistence.noteRepository)
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)
        let richId = UUID()
        try await repo.insert(Block(
            id: richId, noteId: note.id, kind: .richText, sortKey: 0,
            payload: .richText(.plain("hello world")), lastModifiedDeviceId: Self.deviceId
        ))

        // 真实窗口管线：NoteWindowContent（主窗口同款）承载 RichTextBlockView。
        let host = NoteWindowHostModel(noteId: note.id, environment: env)
        await host.load()
        let content = NoteWindowContent(noteId: note.id, host: host, environment: env, coordinator: coordinator)
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        // 首个渲染稳定（.task 建 bridge + 编辑器实例化）——并等 .task 内的
        // `host.load()` 落定：它异步重取 DB，若在插入后完成会覆盖内存块表。
        try await waitUntil {
            !allTextViews(in: hosting).isEmpty
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        try await waitUntil {
            host.blocks.count == 1
        }
        let primary = try #require(allTextViews(in: hosting).first)
        _ = window.makeFirstResponder(primary)
        primary.setSelectedRange(NSRange(location: 5, length: 0))
        primary.delegate?.textViewDidChangeSelection?(Notification(name: NSTextView.didChangeSelectionNotification, object: primary))

        // 工具栏同款目标解析：真实编辑器管线发布的 caret 进入 registry。
        let context = EditorSelectionContext.current(for: note.id)
        let resolved = NoteWindowDerivations.resolveInsertionTarget(blocks: host.blocks, context: context)
        if NSApp.isActive {
            #expect(resolved == .caretSplit(blockId: richId, offset: 5),
                    "the real view pipeline must publish the caret into the insertion registry")
        }

        // 以解析出的目标插入（无头环境未激活时降级 append——同真实降级语义）。
        guard let todoId = await host.insertTodoBlock(target: resolved) else {
            Issue.record("insertTodoBlock failed")
            window.close()
            return
        }
        if resolved == .caretSplit(blockId: richId, offset: 5) {
            #expect(host.blocks.count == 3, "caretSplit must produce leading + todo + trailing")
        }

        // 插入后焦点必须落在新 Todo 编辑器（真实 first responder 断言）。
        var todoEditor: NSTextView?
        for _ in 0..<100 {
            let editors = allTextViews(in: hosting)
            if let todo = editors.first(where: { $0.string.isEmpty && $0 !== primary }),
               window.firstResponder === todo {
                todoEditor = todo
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(todoEditor != nil, "focus must land in the inserted todo editor")

        // 空白回归（2026-08-13 用户实测）：插入后主纸面必须收缩——320pt
        // 最小高度仅在主纸面是笔记全部内容时生效。
        if let paper = primary as? NotePaperTextView {
            #expect(paper.minimumHeight == 0,
                    "the primary paper must drop its 320pt minimum once blocks follow it")
            #expect(paper.intrinsicContentSize.height < 320,
                    "the primary paper must size to content after insertion (gap regression)")
        }

        let blockCountBeforeTyping = host.blocks.count
        #expect(host.blocks.contains { $0.id == todoId }, "the inserted todo block must exist before typing")

        // 回归核心：插入后在正文里继续打字，不得抹掉插入的块（旧实现以
        // 首次渲染的 blocks 快照提交——真实 App 里 Todo/尾部块被清掉）。
        primary.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: primary))
        try await waitUntil {
            host.blocks.contains { $0.id == todoId } && host.blocks.count == blockCountBeforeTyping
        }
        #expect(host.blocks.count == blockCountBeforeTyping,
                "typing in the body must not wipe the inserted blocks (stale-parent regression)")
        #expect(host.blocks.contains { $0.id == todoId },
                "the inserted todo must survive body typing")
        if blockCountBeforeTyping == 3 {
            let trailing = host.blocks.first { $0.kind == .richText && $0.id != richId }
            if case .richText(let doc) = trailing?.payload {
                #expect(doc.text == " world", "the trailing half must survive body typing")
            }
        }

        // ⌘Z 等价：共享撤销栈恢复插入前文档。
        #expect(host.undoManager.canUndo, "insertion must be undoable in the real pipeline")
        host.undoManager.undo()
        try await waitUntil {
            host.blocks.count == 1
        }
        #expect(host.blocks.first?.payload == .richText(.plain("hello world")),
                "undo must restore the pre-insert single block")

        window.close()
        NoteWindowBridge.unregister(noteId: note.id)
    }

    // MARK: - Document continuation (Goal continuation / Test Group D,
    // 004 修复 2026-08-14, P0)
    //
    // The tail continuation: after a trailing todo/code the user must be
    // able to click below it and keep writing plain paragraphs — without
    // ever materializing duplicate empty paragraphs.

    private func makeHost(
        env: AppEnvironment,
        blocks: [Block]
    ) async throws -> NoteWindowHostModel {
        let repo = try #require(env.persistence.noteRepository)
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)
        for block in blocks {
            try await repo.insert(Block(
                id: block.id, noteId: note.id, kind: block.kind,
                sortKey: block.sortKey, payload: block.payload,
                lastModifiedDeviceId: block.lastModifiedDeviceId
            ))
        }
        let host = NoteWindowHostModel(noteId: note.id, environment: env)
        await host.load()
        return host
    }

    /// Case 1: [richText, todo] → a NEW empty paragraph lands last and
    /// receives the focus request.
    @Test
    func continuationAfterTrailingTodoMaterializesParagraph() async throws {
        let env = try makeEnvironment()
        let richId = UUID()
        let todoBlockId = UUID()
        let host = try await makeHost(env: env, blocks: [
            Block(id: richId, noteId: UUID(), kind: .richText, sortKey: 0,
                  payload: .richText(.plain("body")), lastModifiedDeviceId: Self.deviceId),
            Block(id: todoBlockId, noteId: UUID(), kind: .todo, sortKey: 1024,
                  payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("task"))),
                  lastModifiedDeviceId: Self.deviceId),
        ])

        await host.continueDocument()

        #expect(host.blocks.count == 3,
                "one paragraph materializes after the todo (got \(host.blocks.count))")
        let ordered = NoteWindowDerivations.orderedBlocks(host.blocks)
        guard let trailing = ordered.last else {
            Issue.record("no blocks")
            return
        }
        #expect(trailing.kind == .richText, "the new paragraph is a rich-text block")
        #expect(trailing.id != richId, "the new paragraph must not replace the opening one")
        if case .richText(let doc) = trailing.payload {
            #expect(doc.text.isEmpty, "the materialized paragraph starts empty")
        }
        #expect(host.pendingFocusRequest == EditorFocusRequest(blockId: trailing.id, position: .start),
                "the new paragraph must receive the focus request")

        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        #expect(persisted.count == 3, "the paragraph persists immediately (structural, FR-141a)")
    }

    /// Case 2: [richText, code] → same behavior after a trailing code block.
    @Test
    func continuationAfterTrailingCodeMaterializesParagraph() async throws {
        let env = try makeEnvironment()
        let richId = UUID()
        let codeId = UUID()
        let host = try await makeHost(env: env, blocks: [
            Block(id: richId, noteId: UUID(), kind: .richText, sortKey: 0,
                  payload: .richText(.plain("body")), lastModifiedDeviceId: Self.deviceId),
            Block(id: codeId, noteId: UUID(), kind: .code, sortKey: 1024,
                  payload: .code(CodePayload(text: "let x = 1", language: nil)),
                  lastModifiedDeviceId: Self.deviceId),
        ])

        await host.continueDocument()

        #expect(host.blocks.count == 3, "one paragraph materializes after the code (got \(host.blocks.count))")
        let ordered = NoteWindowDerivations.orderedBlocks(host.blocks)
        #expect(ordered.last?.kind == .richText, "the new paragraph is last")
        guard let trailing = ordered.last else { return }
        #expect(host.pendingFocusRequest == EditorFocusRequest(blockId: trailing.id, position: .start))
    }

    /// Case 3: [richText, todo, richText("")] → NO new block; the existing
    /// trailing paragraph is focused with the caret at its END.
    @Test
    func continuationWithExistingTrailingParagraphDoesNotDuplicate() async throws {
        let env = try makeEnvironment()
        let richId = UUID()
        let todoBlockId = UUID()
        let trailingId = UUID()
        let host = try await makeHost(env: env, blocks: [
            Block(id: richId, noteId: UUID(), kind: .richText, sortKey: 0,
                  payload: .richText(.plain("body")), lastModifiedDeviceId: Self.deviceId),
            Block(id: todoBlockId, noteId: UUID(), kind: .todo, sortKey: 1024,
                  payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("task"))),
                  lastModifiedDeviceId: Self.deviceId),
            Block(id: trailingId, noteId: UUID(), kind: .richText, sortKey: 1536,
                  payload: .richText(.plain("")), lastModifiedDeviceId: Self.deviceId),
        ])

        await host.continueDocument()

        #expect(host.blocks.count == 3,
                "no duplicate paragraph may materialize (got \(host.blocks.count))")
        #expect(host.pendingFocusRequest == EditorFocusRequest(blockId: trailingId, position: .end),
                "the existing trailing paragraph must be focused at its end")
    }

    /// Case 4: [todo, code] (no rich-text block at all) → a paragraph is
    /// appended and focused.
    @Test
    func continuationWithOnlySpecialBlocksAppendsParagraph() async throws {
        let env = try makeEnvironment()
        let todoBlockId = UUID()
        let codeId = UUID()
        let host = try await makeHost(env: env, blocks: [
            Block(id: todoBlockId, noteId: UUID(), kind: .todo, sortKey: 100,
                  payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("task"))),
                  lastModifiedDeviceId: Self.deviceId),
            Block(id: codeId, noteId: UUID(), kind: .code, sortKey: 200,
                  payload: .code(CodePayload(text: "let x = 1", language: nil)),
                  lastModifiedDeviceId: Self.deviceId),
        ])

        await host.continueDocument()

        #expect(host.blocks.count == 3, "a paragraph appends after the special blocks (got \(host.blocks.count))")
        let ordered = NoteWindowDerivations.orderedBlocks(host.blocks)
        guard let trailing = ordered.last else { return }
        #expect(trailing.kind == .richText, "the appended block is a rich-text paragraph")
        #expect(host.pendingFocusRequest == EditorFocusRequest(blockId: trailing.id, position: .start))
    }

    /// The real pipeline: [richText("head"), todo, richText("tail text")]
    /// → the continuation click focuses the EXISTING trailing paragraph
    /// with the caret at its text END (not start).
    @Test
    func continuationFocusesTrailingParagraphAtTextEnd() async throws {
        let env = try makeEnvironment()
        let coordinator = NoteWindowCoordinator(environment: env)
        let repo = try #require(env.persistence.noteRepository)
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)
        let richId = UUID()
        let todoBlockId = UUID()
        let trailingId = UUID()
        try await repo.insert(Block(
            id: richId, noteId: note.id, kind: .richText, sortKey: 0,
            payload: .richText(.plain("head")), lastModifiedDeviceId: Self.deviceId
        ))
        try await repo.insert(Block(
            id: todoBlockId, noteId: note.id, kind: .todo, sortKey: 1024,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("task"))),
            lastModifiedDeviceId: Self.deviceId
        ))
        try await repo.insert(Block(
            id: trailingId, noteId: note.id, kind: .richText, sortKey: 1536,
            payload: .richText(.plain("tail text")), lastModifiedDeviceId: Self.deviceId
        ))

        let host = NoteWindowHostModel(noteId: note.id, environment: env)
        await host.load()
        let content = NoteWindowContent(noteId: note.id, host: host, environment: env, coordinator: coordinator)
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        try await waitUntil {
            !allTextViews(in: hosting).isEmpty
        }

        await host.continueDocument()

        // The trailing editor must become first responder with the caret
        // at the END of "tail text".
        var trailingEditor: NSTextView?
        for _ in 0..<100 {
            if let editor = allTextViews(in: hosting).first(where: { $0.string == "tail text" }),
               window.firstResponder === editor {
                trailingEditor = editor
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let editor = try #require(trailingEditor, "the trailing paragraph must become first responder")
        #expect(editor.selectedRange().location == ("tail text" as NSString).length,
                "the caret must land at the END of the trailing paragraph, got \(editor.selectedRange().location)")
        #expect(host.blocks.count == 3, "no block may materialize when a trailing paragraph exists")

        window.close()
        NoteWindowBridge.unregister(noteId: note.id)
    }

    // MARK: - Format overlay resize refresh (Test Group H, 004 修复
    // 2026-08-14, P0)
    //
    // A window resize reflows soft-wrapped text; the selection rect the
    // contextual format row anchors to must be RECOMPUTED at the new
    // layout — never the stale pre-resize rect.

    @Test
    func selectionRectRefreshesAfterResizeReflow() async throws {
        let env = try makeEnvironment()
        let coordinator = NoteWindowCoordinator(environment: env)
        let repo = try #require(env.persistence.noteRepository)
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)
        try await repo.insert(Block(
            noteId: note.id, kind: .richText, sortKey: 0,
            payload: .richText(.plain(
                String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 16)
            )),
            lastModifiedDeviceId: Self.deviceId
        ))

        let host = NoteWindowHostModel(noteId: note.id, environment: env)
        await host.load()
        let content = NoteWindowContent(noteId: note.id, host: host, environment: env, coordinator: coordinator)
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        try await waitUntil {
            !allTextViews(in: hosting).isEmpty
        }
        // The bridge is created in the view's `.task` — wait for it
        // BEFORE publishing the selection (the coordinator attaches the
        // bridge on the next update pass).
        try await waitUntil {
            EditorSelectionContext.bridges[note.id] != nil
        }
        let bridge = try #require(EditorSelectionContext.bridges[note.id], "the bridge must exist after the view's task")
        let primary = try #require(allTextViews(in: hosting).first)

        // Selection setup can still race the attach pass AND parallel
        // suites stealing key-window status (the bridge's authority
        // filter drops non-key publishes) — re-assert the window and
        // retry until the selection is published (bounded).
        var published = false
        for _ in 0..<100 {
            window.makeKeyAndOrderFront(nil)
            _ = window.makeFirstResponder(primary)
            primary.setSelectedRange(NSRange(location: 0, length: 120))
            primary.delegate?.textViewDidChangeSelection?(Notification(name: NSTextView.didChangeSelectionNotification, object: primary))
            if bridge.selectionRectInWindow != nil {
                published = true
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard published else {
            Issue.record("the selection never published through the bridge")
            window.close()
            NoteWindowBridge.unregister(noteId: note.id)
            return
        }
        let wideRect = try #require(bridge.selectionRectInWindow)
        // usedRect (unfloored layout height — the intrinsic is floored at
        // the 320pt only-block click target) proves the reflow.
        let layoutManager = try #require(primary.layoutManager)
        let container = try #require(primary.textContainer)
        layoutManager.ensureLayout(for: container)
        let wideUsed = layoutManager.usedRect(for: container).height

        // Resize the window narrower — the text must reflow. (setFrame +
        // display drives the layout immediately; setContentSize alone left
        // the content at its old width in the headless host.)
        window.setFrame(NSRect(x: 0, y: 0, width: 320, height: 700), display: true)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        try await waitUntil {
            let current = bridge.selectionRectInWindow
            return current != nil && current != wideRect
        }
        let narrowRect = try #require(bridge.selectionRectInWindow)
        layoutManager.ensureLayout(for: container)
        let narrowUsed = layoutManager.usedRect(for: container).height
        // The republished rect must reflect the NEW layout: `firstRect` is
        // the range's FIRST line (a single-line rect), so the first line
        // fragment NARROWS with the window — and the reflow itself must
        // have wrapped the paragraph into more lines.
        #expect(narrowRect.maxX < wideRect.maxX - 20,
                "the selection rect must be recomputed at the new width (\(wideRect.maxX) → \(narrowRect.maxX))")
        #expect(narrowUsed > wideUsed,
                "the paragraph must reflow into more lines at 320 (\(wideUsed) → \(narrowUsed), frame \(primary.frame), container \(container.containerSize))")

        window.close()
        NoteWindowBridge.unregister(noteId: note.id)
    }
}
