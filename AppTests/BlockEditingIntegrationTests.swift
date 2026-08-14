import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
import EditorCore
import Persistence
@testable import StickyNotes

// MARK: - Block editing integration (2026-08-14 用户实测回归)
//
// 用户实测（2026-08-14）：① todo 尾 Return 出现空正文段但光标仍留在
// todo 末尾（焦点未移交新块）；② ⌘A 整篇全选与拖选跨块无效。轻量单元
// 测试全绿但真实窗口链路（NoteWindowContent → RichTextBlockView →
// NSTextView）存在接线断点——本套件走真实管线复现并钉住。

@MainActor
@Suite struct BlockEditingIntegrationTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000060")!

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
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.blockedit.\(UUID().uuidString)") ?? .standard)
        )
    }

    private func makeHost(env: AppEnvironment) async throws -> NoteWindowHostModel {
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            throw TestFailure.blankNoteFailed
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        return host
    }

    private enum TestFailure: Error {
        case blankNoteFailed
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
        timeout: Duration = .seconds(4),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("condition not met within \(timeout)")
    }

    private func makeWindow(
        env: AppEnvironment,
        host: NoteWindowHostModel
    ) async throws -> (NSWindow, NoteWindowCoordinator) {
        let coordinator = NoteWindowCoordinator(environment: env)
        let content = NoteWindowContent(
            noteId: host.noteId,
            host: host,
            environment: env,
            coordinator: coordinator
        )
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
        try await Task.sleep(nanoseconds: 50_000_000)
        return (window, coordinator)
    }

    // MARK: - ① todo 尾 Return 焦点移交

    @Test
    func todoTailReturnMovesFocusToNewParagraphBlock() async throws {
        let env = try makeEnvironment()
        let host = try await makeHost(env: env)
        guard let todoId = await host.insertTodoBlock() else {
            Issue.record("todo insert failed"); return
        }
        // Give the todo text + a caret position at its end.
        var blocks = host.blocks
        guard let idx = blocks.firstIndex(where: { $0.id == todoId }) else {
            Issue.record("todo block missing"); return
        }
        blocks[idx] = Block(
            id: todoId, noteId: host.noteId, kind: .todo, sortKey: blocks[idx].sortKey,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("task"))),
            lastModifiedDeviceId: Self.deviceId
        )
        host.updateBlocks(blocks, isStructural: true)
        await host.flush()

        let (window, _) = try await makeWindow(env: env, host: host)
        defer { window.close() }
        // Find the todo editor (the only editor holding "task").
        let todoEditor = try #require(
            allTextViews(in: window.contentView ?? NSView()).first { $0.string == "task" },
            "the todo editor must exist"
        )
        window.makeFirstResponder(todoEditor)
        todoEditor.setSelectedRange(NSRange(location: 4, length: 0))

        // A PHYSICAL Return key event (the user's real path — keyDown →
        // interpretKeyEvents → insertNewline: → doCommand).
        let returnEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
        todoEditor.keyDown(with: returnEvent)

        // A new empty paragraph block appears AFTER the todo…
        try await waitUntil {
            host.blocks.count == 3 && host.blocks[2].kind == .richText
                && (host.blocks[2].payload.richTextText ?? "").isEmpty
        }
        // …and the FIRST RESPONDER moves into it and STAYS there (the
        // user-visible symptom is a lingering todo caret — a focus that is
        // briefly granted then stolen back must fail this assertion).
        // The new paragraph is host.blocks[2] — resolve ITS editor via the
        // registry (the first empty editor is the blank note's opening
        // paragraph, NOT the inserted one).
        let newBlockId = try #require(host.blocks.dropFirst(2).first?.id,
                                      "the inserted paragraph must be the third block")
        let newEditor = try #require(EditorRegistry.textView(for: newBlockId),
                                     "the new paragraph's editor must be registered")
        // Observe the focus state over time — the user-visible symptom is a
        // lingering todo caret; log what the first responder actually is.
        var observed: String = "?"
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(100))
            observed = String(describing: window.firstResponder)
            if window.firstResponder === newEditor { break }
        }
        try await Task.sleep(for: .milliseconds(600))
        #expect(window.firstResponder === newEditor,
                "the focus must STAY on the new paragraph (observed '\(observed)', now \(String(describing: window.firstResponder)))")
        #expect(window.firstResponder !== todoEditor,
                "the todo editor must NOT regain focus")
    }

    // MARK: - ② ⌘A 整篇全选

    @Test
    func selectAllSelectsEveryBlockInRealWindow() async throws {
        let env = try makeEnvironment()
        let host = try await makeHost(env: env)
        var blocks = host.blocks
        blocks[0] = Block(
            id: blocks[0].id, noteId: host.noteId, kind: .richText, sortKey: blocks[0].sortKey,
            payload: .richText(.plain("first")),
            lastModifiedDeviceId: Self.deviceId
        )
        blocks.append(Block(
            noteId: host.noteId, kind: .richText, sortKey: 1024,
            payload: .richText(.plain("second")),
            lastModifiedDeviceId: Self.deviceId
        ))
        host.updateBlocks(blocks, isStructural: true)
        await host.flush()

        let (window, _) = try await makeWindow(env: env, host: host)
        defer { window.close() }
        let editors = allTextViews(in: window.contentView ?? NSView())
        let firstEditor = try #require(editors.first { $0.string == "first" })
        // The cross-block machinery locates editors via EditorRegistry —
        // assert the real window registered them.
        #expect(EditorRegistry.textView(for: blocks[0].id) !== nil,
                "the first block's editor must be registered")
        #expect(EditorRegistry.textView(for: blocks[1].id) !== nil,
                "the second block's editor must be registered")
        window.makeFirstResponder(firstEditor)

        // Chain decomposition: onSelectAll closure → coordinator.selectAllInNote
        // → parent.onSelectAllInNote → bridge.selectAll.
        let coordinator = firstEditor.delegate as? RichTextView.Coordinator
        #expect(coordinator !== nil, "the editor must be backed by a RichTextView coordinator")
        #expect(coordinator?.parent.onSelectAllInNote != nil,
                "the coordinator's parent must carry the select-all closure")
        coordinator?.selectAllInNote()

        try await waitUntil {
            let editors = allTextViews(in: window.contentView ?? NSView())
            return editors.first { $0.string == "first" }?.selectedRange().length == 5
                && editors.first { $0.string == "second" }?.selectedRange().length == 6
        }
        let bridge = EditorSelectionContext.bridges[host.noteId]
        #expect(bridge?.crossBlockSelection?.selections.count == 2,
                "the bridge enters the cross-block mode (got \(bridge?.crossBlockSelection?.selections.count ?? -1))")
    }

    // MARK: - ③ 拖选跨块（真实事件派发路径）

    @Test
    func dragAcrossBlocksViaRealEventPath() async throws {
        let env = try makeEnvironment()
        let host = try await makeHost(env: env)
        var blocks = host.blocks
        blocks[0] = Block(
            id: blocks[0].id, noteId: host.noteId, kind: .richText, sortKey: blocks[0].sortKey,
            payload: .richText(.plain("Hello upper")),
            lastModifiedDeviceId: Self.deviceId
        )
        blocks.append(Block(
            noteId: host.noteId, kind: .richText, sortKey: 1024,
            payload: .richText(.plain("lower world")),
            lastModifiedDeviceId: Self.deviceId
        ))
        host.updateBlocks(blocks, isStructural: true)
        await host.flush()

        let (window, _) = try await makeWindow(env: env, host: host)
        defer { window.close() }
        let editors = allTextViews(in: window.contentView ?? NSView())
        let upper = try #require(editors.first { $0.string == "Hello upper" })
        let lower = try #require(editors.first { $0.string == "lower world" })
        // The upper block must sit ABOVE the lower one in the window.
        let upperFrame = upper.convert(upper.bounds, to: nil)
        let lowerFrame = lower.convert(lower.bounds, to: nil)
        #expect(upperFrame.minY > lowerFrame.minY, "the upper editor renders above the lower one")

        func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )!
        }

        // A real event path: mouseDown on the upper block's text line, then
        // drag to the lower block's text line. The test host's app is not
        // active, so window.sendEvent consumes the first click on
        // activation — dispatch directly (the real app is active and its
        // events reach the editors). The editors are ONE LINE tall
        // (content-sized) — the drag point must sit inside the line.
        let upperPoint = upper.convert(NSPoint(x: 30, y: 14), to: nil)
        let lowerPoint = lower.convert(NSPoint(x: 40, y: 8), to: nil)
        let hit = window.contentView?.hitTest(upperPoint)
        #expect(hit === upper || hit?.isDescendant(of: upper) == true,
                "hitTest must resolve to the upper editor (got \(String(describing: hit)))")
        upper.mouseDown(with: mouseEvent(.leftMouseDown, at: upperPoint))
        upper.mouseDragged(with: mouseEvent(.leftMouseDragged, at: lowerPoint))

        // The upper block pins [anchor, end]; the lower selects from its
        // start; the bridge enters the cross-block mode.
        let upperLength = (upper.string as NSString).length
        try await waitUntil {
            upper.selectedRange().length == upperLength - upper.selectedRange().location
                && lower.selectedRange().location == 0 && lower.selectedRange().length > 0
        }
        let bridge = EditorSelectionContext.bridges[host.noteId]
        #expect(bridge?.crossBlockSelection?.selections.count == 2,
                "the drag enters the cross-block mode (got \(bridge?.crossBlockSelection?.selections.count ?? -1))")
    }
}

private extension CanonicalBlockPayload {
    var richTextText: String? {
        if case .richText(let doc) = self { return doc.text }
        return nil
    }
}
