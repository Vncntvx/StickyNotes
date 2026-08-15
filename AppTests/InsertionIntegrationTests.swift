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
            persistence: PersistenceServices(store: store),
            assets: AssetServices(directoryURL: assetRoot, store: assetStore),
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

    // MARK: caret-split edge semantics (004 修复 2026-08-13)
    //
    // Caret at END must never spawn an empty trailing block (the reported
    // Add-Todo/Add-Code bug); caret at the START of a secondary block
    // inserts before it; an entirely empty block is REPLACED.

    /// Seeds the primary rich-text block with the given text.
    private func seedRichText(_ host: NoteWindowHostModel, text: String) async throws -> UUID {
        var blocks = host.blocks
        guard let richId = blocks.first(where: { $0.kind == .richText })?.id else {
            throw TestError.failed("no rich-text block")
        }
        blocks = blocks.map { block in
            guard block.id == richId else { return block }
            return Block(
                id: block.id, noteId: block.noteId, kind: .richText,
                sortKey: block.sortKey,
                payload: .richText(.plain(text)),
                versionId: block.versionId, parentVersionId: block.parentVersionId,
                lastModifiedDeviceId: block.lastModifiedDeviceId,
                createdAt: block.createdAt, modifiedAt: Date()
            )
        }
        host.updateBlocks(blocks)
        await host.flush()
        return richId
    }

    @Test
    func caretAtEndWithoutTrailingNewlineLeavesNoEmptyBlock() async throws {
        let (env, _) = try makeEnvironment()
        let (host, _) = try await makeHost(env: env)
        let richId = try await seedRichText(host, text: "alpha")

        guard let todoId = await host.insertTodoBlock(target: .caretSplit(blockId: richId, offset: 5)) else {
            Issue.record("targeted insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        #expect(persisted.count == 2, "caret at end must not spawn an empty trailing block (got \(persisted.count))")
        guard let rich = persisted.first(where: { $0.id == richId }),
              case .richText(let doc) = rich.payload else {
            Issue.record("rich block missing")
            return
        }
        #expect(doc.text == "alpha", "the block keeps its text (id preserved)")
        guard let todo = persisted.first(where: { $0.id == todoId }) else {
            Issue.record("todo block missing")
            return
        }
        #expect(rich.sortKey < todo.sortKey, "the new block lands after the text")
    }

    @Test
    func caretAtEndConsumesTheTrailingEmptyLine() async throws {
        let (env, _) = try makeEnvironment()
        let (host, _) = try await makeHost(env: env)
        let richId = try await seedRichText(host, text: "alpha\n")

        guard let codeId = await host.insertCodeBlock(target: .caretSplit(blockId: richId, offset: 6)) else {
            Issue.record("targeted insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        #expect(persisted.count == 2, "the empty paragraph is consumed, not materialized")
        guard let rich = persisted.first(where: { $0.id == richId }),
              case .richText(let doc) = rich.payload else {
            Issue.record("rich block missing")
            return
        }
        #expect(doc.text == "alpha", "the trailing newline is consumed")
        guard let code = persisted.first(where: { $0.id == codeId }) else {
            Issue.record("code block missing")
            return
        }
        #expect(rich.sortKey < code.sortKey)
    }

    @Test
    func caretAtStartOfSecondaryBlockInsertsBeforeWithoutEmptyLeading() async throws {
        let (env, _) = try makeEnvironment()
        let (host, _) = try await makeHost(env: env)
        let richId = try await seedRichText(host, text: "alpha beta")
        // Split in the middle first: [rich "alpha", code, rich " beta"].
        guard let codeId = await host.insertCodeBlock(target: .caretSplit(blockId: richId, offset: 5)) else {
            Issue.record("code insert failed")
            return
        }
        let split = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        guard let trailing = split.last(where: { $0.kind == .richText }) else {
            Issue.record("trailing block missing")
            return
        }
        // Now insert at the very START of the trailing block.
        guard let todoId = await host.insertTodoBlock(target: .caretSplit(blockId: trailing.id, offset: 0)) else {
            Issue.record("todo insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        let richTexts = persisted.filter { $0.kind == .richText }
        #expect(richTexts.count == 2, "no empty leading block (got \(richTexts.count) rich-text blocks)")
        #expect(!persisted.contains { block in
            if case .richText(let doc) = block.payload { return doc.text.isEmpty }
            return false
        }, "no empty rich-text block survives")
        guard let code = persisted.first(where: { $0.id == codeId }),
              let todo = persisted.first(where: { $0.id == todoId }),
              let trailingAfter = persisted.first(where: { $0.id == trailing.id }) else {
            Issue.record("blocks missing")
            return
        }
        #expect(code.sortKey < todo.sortKey && todo.sortKey < trailingAfter.sortKey,
                "the new block lands before the split's trailing text")
    }

    @Test
    func caretSplitOnEntirelyEmptyBlockReplacesIt() async throws {
        let (env, _) = try makeEnvironment()
        let (host, _) = try await makeHost(env: env)
        let blocksBefore = host.blocks
        guard let richId = blocksBefore.first(where: { $0.kind == .richText })?.id else {
            Issue.record("no primary block")
            return
        }
        // A fresh note is ONE empty rich-text block — the insertion REPLACES it.
        guard let todoId = await host.insertTodoBlock(target: .caretSplit(blockId: richId, offset: 0)) else {
            Issue.record("todo insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        #expect(persisted.count == 1, "the empty block is replaced, not split")
        #expect(persisted.first?.id == todoId)
        #expect(persisted.first?.kind == .todo)
    }

    @Test
    func caretAtStartOfPrimarySurfaceKeepsZeroHeightLeadingSlot() async throws {
        // The primary rich-text surface renders pinned ABOVE every secondary
        // block — inserting before the caret at its very start keeps the
        // (empty) leading half as the 0pt primary slot so the new block
        // visually lands above the text; FR-050a removes the emptied slot on
        // focus exit.
        let (env, _) = try makeEnvironment()
        let (host, _) = try await makeHost(env: env)
        let richId = try await seedRichText(host, text: "alpha")
        guard let todoId = await host.insertTodoBlock(target: .caretSplit(blockId: richId, offset: 0)) else {
            Issue.record("todo insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        #expect(persisted.count == 3)
        guard let primary = persisted.first(where: { $0.id == richId }),
              case .richText(let doc) = primary.payload,
              let todo = persisted.first(where: { $0.id == todoId }),
              let trailing = persisted.last(where: { $0.kind == .richText }) else {
            Issue.record("expected blocks missing")
            return
        }
        #expect(doc.text.isEmpty, "the primary keeps the empty leading slot (0pt, self-heals)")
        #expect(trailing.id != richId)
        if case .richText(let trailingDoc) = trailing.payload {
            #expect(trailingDoc.text == "alpha")
        } else {
            Issue.record("trailing not richText")
        }
        #expect(primary.sortKey < todo.sortKey && todo.sortKey < trailing.sortKey)
    }
}
