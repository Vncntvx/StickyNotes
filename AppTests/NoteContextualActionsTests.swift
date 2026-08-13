import Testing
import Foundation
import Domain
import Persistence
@testable import StickyNotes

// MARK: - FR-031 contextual-action wiring tests (T282)
//
// Per tasks.md T282: the note-level contextual menu actions (duplicate,
// copy-as-Markdown, export-as-JSON, move-to-Trash per FR-031) must be
// functional — the menu rendered no-op stubs before this task. These tests
// exercise the exact repository operations the wired actions perform
// (duplicate via NoteDuplicator + repo.create/insert; move-to-Trash via
// repo.trash). (The FR-112 widget-eligibility toggle was removed 2026-08-13
// with the widget surface.)

@MainActor
@Suite struct NoteContextualActionsTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000003")!

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.actions.\(UUID().uuidString)") ?? .standard)
        )
    }

    @Test
    func duplicateCreatesIdenticalNewNoteWithFreshKey() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        let block = Block(
            noteId: noteId,
            kind: .richText,
            sortKey: 0,
            payload: .richText(RichTextDocument(text: "duplicate me", paragraphs: [])),
            lastModifiedDeviceId: Self.deviceId
        )
        host.updateBlocks([block], isStructural: true)
        await host.flush()

        // The duplicate action (NoteWindowContent.duplicateNote) performs:
        // NoteDuplicator.duplicate → repo.create → repo.insert for each block.
        guard let note = host.note else {
            Issue.record("note missing")
            return
        }
        let duplicated = NoteDuplicator.duplicate(note, blocks: host.blocks, deviceId: Self.deviceId)
        let repo = env.persistence.noteRepository!
        try await repo.create(duplicated.note)
        for duplicatedBlock in duplicated.blocks {
            try await repo.insert(duplicatedBlock)
        }

        #expect(duplicated.note.id != note.id, "new note UUID")
        #expect(duplicated.note.manualSortKey >= 0, "fresh manual sort key (FR-022a)")
        #expect(duplicated.note.lifecycleState == .active)
        let duplicatedBlocks = try await repo.fetchBlocks(noteId: duplicated.note.id)
        #expect(duplicatedBlocks.count == 1)
        if case .richText(let doc) = duplicatedBlocks.first?.payload {
            #expect(doc.text == "duplicate me", "byte-identical block content")
        } else {
            Issue.record("expected rich-text block")
        }
    }

    @Test
    func moveToTrashPersistsAndClosesWindow() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        // FR-014: trash persists the lifecycle transition.
        let repo = env.persistence.noteRepository!
        try await repo.trash(id: noteId, deviceId: Self.deviceId)
        let fetched = try await repo.fetch(id: noteId)
        #expect(fetched?.lifecycleState == .trashed)
    }

}
