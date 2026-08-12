import Testing
import Foundation
import AppKit
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
