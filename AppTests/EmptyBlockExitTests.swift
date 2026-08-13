import Testing
import Foundation
import Domain
import Persistence
import AssetStore
import SystemBridge
@testable import StickyNotes

// MARK: - Empty-block exit tests (004 修复 2026-08-13, P1-6)
//
// FR-050a: when the cursor EXITS an emptied todo/code block, the block
// merges away (BlockMergeOperation.decide — the final block is never
// removed, IME composition suppresses removal). Todo blocks route through
// the host so the cascade-deleted TodoItem row restores in the SAME undo
// group (a view-level structural swap would resurrect the block without its
// row — broken checkbox state after ⌘Z).

@MainActor
@Suite struct EmptyBlockExitTests {

    private let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000025")!

    private func makeEnvironment() throws -> (AppEnvironment, URL) {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let assetRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-exit-tests-\(UUID().uuidString)", isDirectory: true)
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
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.emptyexit.\(UUID().uuidString)") ?? .standard)
        )
        return (env, assetRoot)
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

    /// Appends a rich-text block with the given text after the current tail.
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
    func emptiedTodoBetweenBlocksIsRemovedWithItsRow() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        guard let todoId = await host.insertTodoBlock() else {
            Issue.record("todo insert failed")
            return
        }
        // [rich "", todo, rich "after"] — the todo has a successor.
        appendRichText(host, text: "after")
        await host.flush()

        await host.removeEmptiedTodoBlock(blockId: todoId)

        #expect(!host.blocks.contains(where: { $0.id == todoId }),
                "the emptied todo leaves the block list (FR-050a)")
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        #expect(!persisted.contains(where: { $0.id == todoId }))
        let item = try await env.persistence.todoRepository!.fetchTodo(blockId: todoId)
        #expect(item == nil, "the TodoItem row goes with the block")
    }

    @Test
    func emptiedFinalTodoIsKept() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        guard let todoId = await host.insertTodoBlock() else {
            Issue.record("todo insert failed")
            return
        }
        await host.flush()

        await host.removeEmptiedTodoBlock(blockId: todoId)

        #expect(host.blocks.contains(where: { $0.id == todoId }),
                "the final block is never removed (keepFinalBlock)")
        let item = try await env.persistence.todoRepository!.fetchTodo(blockId: todoId)
        #expect(item != nil)
    }

    @Test
    func nonEmptyTodoIsKept() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        guard let todoId = await host.insertTodoBlock() else {
            Issue.record("todo insert failed")
            return
        }
        // Give the todo text, then add a successor.
        var blocks = host.blocks
        blocks = blocks.map { block in
            guard block.id == todoId, case .todo(let payload) = block.payload else { return block }
            return Block(
                id: block.id, noteId: block.noteId, kind: .todo, sortKey: block.sortKey,
                payload: .todo(TodoPayload(todoId: payload.todoId, richText: .plain("buy milk"))),
                versionId: block.versionId, parentVersionId: block.parentVersionId,
                lastModifiedDeviceId: block.lastModifiedDeviceId,
                createdAt: block.createdAt, modifiedAt: Date()
            )
        }
        host.updateBlocks(blocks, isStructural: true)
        appendRichText(host, text: "after")
        await host.flush()

        await host.removeEmptiedTodoBlock(blockId: todoId)

        #expect(host.blocks.contains(where: { $0.id == todoId }),
                "a todo with text survives the cursor exit")
    }

    @Test
    func emptiedTodoWithChildrenIsKept() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        guard let parentId = await host.insertTodoBlock() else {
            Issue.record("todo insert failed")
            return
        }
        // A child indented under the (empty) parent.
        await host.insertTodoBlock()
        let children = host.blocks.filter { $0.kind == .todo }.map(\.id)
        guard let childId = children.first(where: { $0 != parentId }) else {
            Issue.record("child todo missing")
            return
        }
        await host.indentTodo(blockId: childId)
        appendRichText(host, text: "after")
        await host.flush()

        await host.removeEmptiedTodoBlock(blockId: parentId)

        #expect(host.blocks.contains(where: { $0.id == parentId }),
                "an emptied todo with children stays — the cascade would orphan them")
        let item = try await env.persistence.todoRepository!.fetchTodo(blockId: parentId)
        #expect(item != nil)
    }
}
