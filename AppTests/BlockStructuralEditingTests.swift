import Testing
import Foundation
import Domain
import Persistence
import AssetStore
import SystemBridge
import EditorCore
@testable import StickyNotes

// MARK: - Block structural editing tests (2026-08-14)
//
// 块首 Backspace 合并（mergeBlockIntoPrevious）、跨块选区删除
// （applySpanningDeletion）与整篇全选选区构造（crossBlockSelectionCoveringAll）
// 的 host 级行为：
// - 合并：文本接到上一块尾、焦点去上一块末尾、todo 块被合并时 TodoItem
//   行与块列表同组 undo；
// - 跨块删除：只删选中字符、空块按 FR-050a 并掉、被删 todo 的行级联、
//   单 undo 组恢复；
// - 全选构造：每块全文 scalar range、尾部空块不入选区。

@MainActor
@Suite struct BlockStructuralEditingTests {

    private let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000026")!

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let assetRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("block-structural-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: assetRoot, withIntermediateDirectories: true)
        let assetStore = try AssetStore(directoryURL: assetRoot)
        return AppEnvironment(
            persistence: PersistenceServices(store: store),
            assets: AssetServices(directoryURL: assetRoot, store: assetStore),
        )
    }

    private func makeHost(env: AppEnvironment) async throws -> NoteWindowHostModel {
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            throw TestError.failed("createBlankNote failed")
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        return host
    }

    enum TestError: Error {
        case failed(String)
    }

    private func appendRichText(_ host: NoteWindowHostModel, text: String) {
        var blocks = host.blocks
        let maxSort = blocks.map(\.sortKey).max() ?? 0
        blocks.append(Block(
            noteId: host.noteId,
            kind: .richText,
            sortKey: maxSort + 1024,
            payload: .richText(.plain(text)),
            lastModifiedDeviceId: deviceId
        ))
        host.updateBlocks(blocks, isStructural: true)
    }

    private func text(of block: Block) -> String? {
        switch block.payload {
        case .richText(let doc): return doc.text
        case .todo(let payload): return payload.richText.text
        case .code(let payload): return payload.text
        default: return nil
        }
    }

    private func waitUntil(
        _ message: String,
        timeout: Duration = .seconds(4),
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                throw TestError.failed(message)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: - mergeBlockIntoPrevious

    @Test
    func mergeBlockIntoPreviousFusesTextAndFocusesPrevious() async throws {
        let env = try makeEnvironment()
        let host = try await makeHost(env: env)
        appendRichText(host, text: "world")
        await host.flush()
        let first = host.blocks[0]
        let second = host.blocks[1]

        await host.mergeBlockIntoPrevious(blockId: second.id)

        #expect(host.blocks.count == 1, "the merged block leaves the list")
        #expect(text(of: host.blocks[0]) == "world", "the previous block carries the fused text")
        #expect(host.pendingFocusRequest?.blockId == first.id,
                "focus moves to the PREVIOUS block")
        #expect(host.pendingFocusRequest?.position == .end, "focus lands at the previous block's end")
    }

    @Test
    func mergeFirstBlockIsNoOp() async throws {
        let env = try makeEnvironment()
        let host = try await makeHost(env: env)
        let before = host.blocks
        let blockId = host.blocks[0].id

        await host.mergeBlockIntoPrevious(blockId: blockId)

        #expect(host.blocks == before, "the first block cannot merge into nothing")
        #expect(host.pendingFocusRequest == nil)
    }

    @Test
    func mergeTodoIntoPreviousCascadesRowAndUndoRestoresBoth() async throws {
        let env = try makeEnvironment()
        let host = try await makeHost(env: env)
        guard let todoId = await host.insertTodoBlock() else {
            Issue.record("todo insert failed"); return
        }
        // Set the todo's text + a successor, so the merge carries text.
        var blocks = host.blocks
        guard let todoIdx = blocks.firstIndex(where: { $0.id == todoId }) else {
            Issue.record("todo block missing"); return
        }
        blocks[todoIdx] = Block(
            id: todoId, noteId: host.noteId, kind: .todo, sortKey: blocks[todoIdx].sortKey,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("task"))),
            lastModifiedDeviceId: deviceId
        )
        host.updateBlocks(blocks, isStructural: true)
        appendRichText(host, text: "after")
        await host.flush()
        let previousCount = host.blocks.count
        let previousFirst = host.blocks[0]

        await host.mergeBlockIntoPrevious(blockId: todoId)

        #expect(host.blocks.count == previousCount - 1, "the todo block is removed")
        #expect(text(of: host.blocks[0]) == "task", "the todo text fuses into the previous block")
        let item = try await env.persistence.todoRepository!.fetchTodo(blockId: todoId)
        #expect(item == nil, "the TodoItem row cascades with the block")

        // Undo restores the block AND its TodoItem row in one group.
        host.undoManager.undo()
        try await waitUntil("undo must restore the todo block") {
            host.blocks.contains(where: { $0.id == todoId })
        }
        let restored = try await env.persistence.todoRepository!.fetchTodo(blockId: todoId)
        #expect(restored != nil, "undo re-inserts the TodoItem row")
        #expect(host.blocks.first?.id == previousFirst.id, "the previous block is restored")
    }

    // MARK: - applySpanningDeletion

    @Test
    func applySpanningDeletionRemovesCharactersAcrossBlocks() async throws {
        let env = try makeEnvironment()
        let host = try await makeHost(env: env)
        // Replace the blank first block's text and append a second.
        var blocks = host.blocks
        blocks[0] = Block(
            id: blocks[0].id, noteId: host.noteId, kind: .richText, sortKey: blocks[0].sortKey,
            payload: .richText(.plain("Hello")),
            lastModifiedDeviceId: deviceId
        )
        host.updateBlocks(blocks, isStructural: true)
        appendRichText(host, text: "world")
        await host.flush()
        let firstId = host.blocks[0].id
        let secondId = host.blocks[1].id

        let selection = CrossBlockSelection(selections: [
            (blockId: firstId, range: 0..<5),   // wipes "Hello"
            (blockId: secondId, range: 0..<3),  // keeps "ld"
        ])
        await host.applySpanningDeletion(selection: selection)

        #expect(host.blocks.count == 1, "the emptied first block merges away (FR-050a)")
        #expect(text(of: host.blocks[0]) == "ld", "only the selected characters are removed")

        host.undoManager.undo()
        try await waitUntil("undo must restore both blocks") {
            host.blocks.count == 2 && host.blocks.contains(where: { $0.id == firstId })
        }
        #expect(host.blocks.contains(where: { $0.id == secondId }))
    }

    @Test
    func spanningDeletionCascadesTodoRows() async throws {
        let env = try makeEnvironment()
        let host = try await makeHost(env: env)
        guard let todoId = await host.insertTodoBlock() else {
            Issue.record("todo insert failed"); return
        }
        var blocks = host.blocks
        guard let todoIdx = blocks.firstIndex(where: { $0.id == todoId }) else {
            Issue.record("todo block missing"); return
        }
        blocks[todoIdx] = Block(
            id: todoId, noteId: host.noteId, kind: .todo, sortKey: blocks[todoIdx].sortKey,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("x"))),
            lastModifiedDeviceId: deviceId
        )
        host.updateBlocks(blocks, isStructural: true)
        // A successor makes the emptied todo mergeable (FR-050a: the FINAL
        // block is kept, so a tail todo would stay with its row intact).
        appendRichText(host, text: "after")
        await host.flush()

        // Delete the todo's whole text: the emptied todo merges away — and
        // the pre-existing empty first block is swept too (FR-050a cascade
        // evaluates every empty block after the deletion).
        let selection = CrossBlockSelection(selections: [
            (blockId: todoId, range: 0..<1),
        ])
        await host.applySpanningDeletion(selection: selection)

        #expect(host.blocks.count == 1, "the emptied todo merges away")
        #expect(text(of: host.blocks[0]) == "after", "the successor survives")
        let item = try await env.persistence.todoRepository!.fetchTodo(blockId: todoId)
        #expect(item == nil, "the TodoItem row cascades with the deleted todo")

        host.undoManager.undo()
        try await waitUntil("undo must restore the todo") {
            host.blocks.contains(where: { $0.id == todoId })
        }
        let restored = try await env.persistence.todoRepository!.fetchTodo(blockId: todoId)
        #expect(restored != nil, "undo re-inserts the TodoItem row")
    }

    // MARK: - crossBlockSelectionCoveringAll

    @Test
    func crossBlockSelectionCoveringAllSkipsTrailingPadding() {
        let noteId = UUID()
        let blocks = [
            Block(noteId: noteId, kind: .richText, sortKey: 0,
                  payload: .richText(.plain("one")), lastModifiedDeviceId: deviceId),
            Block(noteId: noteId, kind: .todo, sortKey: 1024,
                  payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("two"))),
                  lastModifiedDeviceId: deviceId),
            Block(noteId: noteId, kind: .richText, sortKey: 2048,
                  payload: .richText(.plain("")), lastModifiedDeviceId: deviceId),
        ]
        let selection = NoteWindowDerivations.crossBlockSelectionCoveringAll(blocks: blocks)
        #expect(selection.selections.count == 2, "the trailing empty padding block is not selectable")
        #expect(selection.selections[0].range == 0..<3)
        #expect(selection.selections[1].range == 0..<3)
    }
}
