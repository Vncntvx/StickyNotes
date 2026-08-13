import Testing
import Foundation
import Domain
import Persistence
import AppKit
@testable import StickyNotes

// MARK: - Editor + appearance persistence tests (T281, US1/US3)
//
// Per tasks.md T281: the note-window host persists editor block changes and
// appearance edits through the repository (FR-141/FR-141a — 500 ms debounce,
// flush on close) and applies the FR-012a auto-discard decision on close.
// Tests: type text → flush → reopen → content preserved (US1 AC3); appearance
// changes survive a "relaunch" (fresh host over the same DB); a never-content
// note is auto-discarded on close while a previously-content note is never
// auto-deleted when emptied.

@MainActor
@Suite struct EditorPersistenceTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000002")!

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
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.editor.\(UUID().uuidString)") ?? .standard)
        )
    }

    private func makeRichTextBlock(noteId: UUID, text: String) -> Block {
        let doc = RichTextDocument(
            text: text,
            paragraphs: [
                RichTextParagraph(
                    startScalar: 0,
                    endScalar: text.unicodeScalars.count,
                    style: .body,
                    runs: [RichTextRun(startScalar: 0, endScalar: text.unicodeScalars.count, marks: [])]
                )
            ]
        )
        return Block(
            noteId: noteId,
            kind: .richText,
            sortKey: 0,
            payload: .richText(doc),
            lastModifiedDeviceId: Self.deviceId
        )
    }

    @Test
    func typeCloseReopenPreservesContent() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }

        // Simulate typing a block into the window.
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        let block = makeRichTextBlock(noteId: noteId, text: "persisted draft content")
        host.updateBlocks([block])
        await host.flush()   // FR-141a flush (window close path)

        // "Reopen": a fresh host over the same database.
        let reopened = NoteWindowHostModel(noteId: noteId, environment: env)
        await reopened.load()
        let fetched = try await env.persistence.noteRepository!.fetchBlocks(noteId: noteId)
        #expect(fetched.count == 1, "the typed block is persisted")
        if case .richText(let doc) = fetched.first?.payload {
            #expect(doc.text == "persisted draft content")
        } else {
            Issue.record("expected a rich-text block")
        }
    }

    @Test
    func appearanceChangesSurviveRelaunch() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        guard var note = host.note else {
            Issue.record("note missing")
            return
        }
        // FR-031/FR-034/FR-040a/FR-041a/FR-043a: appearance edits.
        note.title = "Renamed Note"
        note.colorKey = .blue
        note.transparency = 0.6
        note.textSize = 18
        note.alwaysOnTop = true
        host.updateAppearance(note)

        // Wait for the immediate structural write.
        try await Task.sleep(nanoseconds: 300_000_000)

        let reopened = NoteWindowHostModel(noteId: noteId, environment: env)
        await reopened.load()
        let fetched = try await env.persistence.noteRepository!.fetch(id: noteId)
        #expect(fetched?.title == "Renamed Note")
        #expect(fetched?.colorKey == .blue)
        #expect(fetched?.transparency == 0.6)
        #expect(fetched?.textSize == 18)
        #expect(fetched?.alwaysOnTop == true)
    }

    @Test
    func neverContentNoteIsAutoDiscardedOnClose() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()

        // FR-012a: a never-contained-content note MAY be removed on close.
        let mayRemove = await host.close()
        #expect(mayRemove, "never-content note may be auto-removed")
    }

    @Test
    func previouslyContentNoteNeverAutoDeletedWhenEmpty() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        let block = makeRichTextBlock(noteId: noteId, text: "x")  // single char = meaningful (FR-012a)
        host.updateBlocks([block])
        await host.flush()

        // Now the text is emptied — but the note previously contained content.
        let empty = makeRichTextBlock(noteId: noteId, text: "   \n ")
        host.updateBlocks([empty])
        await host.flush()
        let mayRemove = await host.close()
        #expect(!mayRemove, "previously-content note MUST NOT be auto-deleted when empty (FR-013/FR-012a)")
    }

    @Test
    func emptyBlockRemovalPersists() async throws {
        // Deleting a block through the host removes it from the database
        // (the autosave sink diffs against the DB).
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        let first = makeRichTextBlock(noteId: noteId, text: "keep")
        let second = makeRichTextBlock(noteId: noteId, text: "remove me")
        host.updateBlocks([first, second], isStructural: true)

        // The user deletes the second block (cursor-exit merge per FR-050a).
        host.updateBlocks([first], isStructural: true)
        await host.flush()
        let fetched = try await env.persistence.noteRepository!.fetchBlocks(noteId: noteId)
        #expect(fetched.map(\.id) == [first.id], "the removed block is deleted from the database")
    }
}
