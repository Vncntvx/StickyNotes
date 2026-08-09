import Testing
import Foundation
import AppKit
import Domain
import Persistence
import AssetStore
import SystemBridge
@testable import StickyNotes

// MARK: - Insertion integration tests (004 T036, spec FR-010/Q4)
//
// Per tasks.md T036: host-level insertion integration — image assets land
// in the AssetStore, all five insertion kinds persist, and the resolved
// insertion targets place blocks at the caret (split), after a special
// block, or at the end.

@MainActor
@Suite struct InsertionIntegrationTests {

    private let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000023")!

    private func makeEnvironment() throws -> (AppEnvironment, URL) {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let assetRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("insertion-tests-\(UUID().uuidString)", isDirectory: true)
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
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.insert.\(UUID().uuidString)") ?? .standard)
        )
        return (env, assetRoot)
    }

    private func makeHost(env: AppEnvironment) async throws -> (NoteWindowHostModel, UUID) {
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            throw TestError.failed("createBlankNote failed")
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        return (host, noteId)
    }

    enum TestError: Error {
        case failed(String)
    }

    @Test
    func imageInsertionPersistsBlockAndAssets() async throws {
        let (env, _) = try makeEnvironment()
        let (host, _) = try await makeHost(env: env)

        // A tiny valid PNG.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("img-\(UUID().uuidString).png")
        try png.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        guard let blockId = await host.insertImageBlock(url: fileURL) else {
            Issue.record("insertImageBlock failed")
            return
        }
        let blocks = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        guard let block = blocks.first(where: { $0.id == blockId }) else {
            Issue.record("image block not persisted")
            return
        }
        #expect(block.kind == .image)
        guard case .image(let payload) = block.payload else {
            Issue.record("expected image payload")
            return
        }
        // The assets must be readable back through the store.
        let original = try await env.assets.store!.readData(assetID: payload.originalAssetId)
        #expect(original == png, "original image bytes land in the asset store")
    }

    @Test
    func allFiveInsertionKindsPersist() async throws {
        let (env, _) = try makeEnvironment()
        let (host, _) = try await makeHost(env: env)

        guard let todoId = await host.insertTodoBlock() else {
            Issue.record("todo insert failed")
            return
        }
        guard let codeId = await host.insertCodeBlock() else {
            Issue.record("code insert failed")
            return
        }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ref-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let refId = await host.insertFileReferenceBlock(
            url: fileURL,
            bookmarkCreator: { _ in Data("fake-bookmark".utf8) }
        ) else {
            Issue.record("file-ref insert failed")
            return
        }
        guard await host.captureRegion(dataProvider: {
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        }) else {
            Issue.record("screenshot insert failed")
            return
        }
        let blocks = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        let kinds = Set(blocks.map(\.kind))
        #expect(kinds.contains(.todo) && kinds.contains(.code) && kinds.contains(.fileRef) && kinds.contains(.screenshot),
                "all window-level insertion kinds persist (FR-010)")
        #expect(blocks.contains { $0.id == todoId }, "todo block id matches")
        #expect(blocks.contains { $0.id == codeId }, "code block id matches")
        #expect(blocks.contains { $0.id == refId }, "file-ref block id matches")
    }

    @Test
    func caretSplitTargetSplitsRichTextBlock() async throws {
        let (env, _) = try makeEnvironment()
        let (host, _) = try await makeHost(env: env)

        // Seed the primary rich-text block with text.
        var blocks = host.blocks
        let richId = blocks.first(where: { $0.kind == .richText })!.id
        blocks = blocks.map { block in
            guard block.id == richId else { return block }
            return Block(
                id: block.id, noteId: block.noteId, kind: .richText,
                sortKey: block.sortKey,
                payload: .richText(.plain("alpha beta")),
                versionId: block.versionId, parentVersionId: block.parentVersionId,
                lastModifiedDeviceId: block.lastModifiedDeviceId,
                createdAt: block.createdAt, modifiedAt: Date()
            )
        }
        host.updateBlocks(blocks)
        await host.flush()

        // Insert a todo AT THE CARET (offset 5 → after "alpha").
        let target = InsertionTarget.caretSplit(blockId: richId, offset: 5)
        guard let todoId = await host.insertTodoBlock(target: target) else {
            Issue.record("targeted insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        let rich = persisted.filter { $0.kind == .richText }.sorted { $0.sortKey < $1.sortKey }
        #expect(rich.count == 2, "the rich-text block splits in two (FR-010)")
        let leading = rich[0]
        let trailing = rich[1]
        if case .richText(let doc) = leading.payload {
            #expect(doc.text == "alpha", "leading part keeps the pre-caret text")
        } else {
            Issue.record("leading not richText")
        }
        if case .richText(let doc) = trailing.payload {
            #expect(doc.text == " beta", "trailing part keeps the post-caret text")
        } else {
            Issue.record("trailing not richText")
        }
        // The new block sits between the two halves.
        guard let todo = persisted.first(where: { $0.id == todoId }) else {
            Issue.record("todo block missing")
            return
        }
        #expect(leading.sortKey < todo.sortKey && todo.sortKey < trailing.sortKey,
                "inserted block lands between the split halves")
    }

    @Test
    func afterBlockTargetInsertsAfterSpecialBlock() async throws {
        let (env, _) = try makeEnvironment()
        let (host, _) = try await makeHost(env: env)
        guard let todoId = await host.insertTodoBlock() else {
            Issue.record("todo insert failed")
            return
        }
        let blocksBefore = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        guard let todo = blocksBefore.first(where: { $0.id == todoId }) else {
            Issue.record("todo block missing")
            return
        }
        let target = InsertionTarget.afterBlock(blockId: todoId)
        guard let codeId = await host.insertCodeBlock(target: target) else {
            Issue.record("targeted code insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        guard let code = persisted.first(where: { $0.id == codeId }) else {
            Issue.record("code block missing")
            return
        }
        #expect(todo.sortKey < code.sortKey, "the new block follows the special block")
    }

    @Test
    func appendTargetIsDefaultBehavior() async throws {
        let (env, _) = try makeEnvironment()
        let (host, _) = try await makeHost(env: env)
        let maxBefore = host.blocks.map(\.sortKey).max() ?? 0
        guard let codeId = await host.insertCodeBlock(target: .append) else {
            Issue.record("append insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        guard let code = persisted.first(where: { $0.id == codeId }) else {
            Issue.record("code block missing")
            return
        }
        #expect(code.sortKey > maxBefore, "append uses a sort key past the current max")
    }
}
