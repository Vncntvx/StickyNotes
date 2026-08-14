import Testing
import Foundation
import Domain
import Persistence
import AssetStore
import SystemBridge
@testable import StickyNotes

// MARK: - Block keyboard deletion tests (2026-08-14)
//
// 空块按键删除（deleteEmptyBlockOnKey）的 host 级行为：
// - 空 todo/code/正文块删除后焦点去下一块开头（Q3-B）；
// - 最后一块空块按键删除是 no-op（keepFinalBlock，FR-050a）；
// - todo 行与块列表同组 undo（经 removeEmptiedTodoBlock 路径）；
// - 非空块按键删除 no-op（按键路由已在视图层拦截，此处防御）。

@MainActor
@Suite struct BlockKeyboardDeletionTests {

    private let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000027")!

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let assetRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("block-key-deletion-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: assetRoot, withIntermediateDirectories: true)
        let assetStore = try AssetStore(directoryURL: assetRoot)
        return AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(directoryURL: assetRoot, store: assetStore),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.blockkeydel.\(UUID().uuidString)") ?? .standard)
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

    @Test
    func deletingEmptyBlockFocusesNextBlockStart() async throws {
        let env = try makeEnvironment()
        let host = try await makeHost(env: env)
        // [rich "", rich "after"] — delete the FIRST (empty) block.
        appendRichText(host, text: "after")
        await host.flush()
        let firstId = host.blocks[0].id
        let nextId = host.blocks[1].id

        await host.deleteEmptyBlockOnKey(blockId: firstId)

        #expect(!host.blocks.contains(where: { $0.id == firstId }),
                "the empty block is removed")
        #expect(host.pendingFocusRequest?.blockId == nextId,
                "focus moves to the NEXT block (Q3-B)")
        #expect(host.pendingFocusRequest?.position == .start)
    }

    @Test
    func deletingFinalEmptyBlockIsNoOp() async throws {
        let env = try makeEnvironment()
        let host = try await makeHost(env: env)
        appendRichText(host, text: "first")
        await host.flush()
        let lastId = host.blocks.last!.id
        let before = host.blocks

        await host.deleteEmptyBlockOnKey(blockId: lastId)

        #expect(host.blocks == before, "the FINAL block is never removed (FR-050a)")
        #expect(host.pendingFocusRequest == nil)
    }

    @Test
    func deletingEmptyTodoCascadesRowAndUndoRestores() async throws {
        let env = try makeEnvironment()
        let host = try await makeHost(env: env)
        guard let todoId = await host.insertTodoBlock() else {
            Issue.record("todo insert failed"); return
        }
        // The todo is empty; give it a successor so it is mergeable.
        appendRichText(host, text: "after")
        await host.flush()

        await host.deleteEmptyBlockOnKey(blockId: todoId)

        #expect(!host.blocks.contains(where: { $0.id == todoId }))
        let item = try await env.persistence.todoRepository!.fetchTodo(blockId: todoId)
        #expect(item == nil, "the TodoItem row cascades with the block")

        host.undoManager.undo()
        let deadline = ContinuousClock.now + .seconds(4)
        while !host.blocks.contains(where: { $0.id == todoId }) {
            if ContinuousClock.now >= deadline {
                Issue.record("undo must restore the todo block")
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let restored = try await env.persistence.todoRepository!.fetchTodo(blockId: todoId)
        #expect(restored != nil, "undo re-inserts the TodoItem row")
    }

    @Test
    func deletingNonEmptyBlockOnKeyIsNoOp() async throws {
        let env = try makeEnvironment()
        let host = try await makeHost(env: env)
        var blocks = host.blocks
        blocks[0] = Block(
            id: blocks[0].id, noteId: host.noteId, kind: .richText, sortKey: blocks[0].sortKey,
            payload: .richText(.plain("text")),
            lastModifiedDeviceId: deviceId
        )
        host.updateBlocks(blocks, isStructural: true)
        await host.flush()
        let before = host.blocks
        let firstId = host.blocks[0].id

        await host.deleteEmptyBlockOnKey(blockId: firstId)

        #expect(host.blocks == before, "the key-routing layer owns non-empty handling; host no-ops")
        #expect(host.pendingFocusRequest == nil)
    }
}
