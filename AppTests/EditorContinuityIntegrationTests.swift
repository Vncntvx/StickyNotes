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
}
