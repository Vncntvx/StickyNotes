import Testing
import Foundation
import Domain
import Persistence
@testable import StickyNotes

// MARK: - Library search wiring tests (T283, US2)
//
// Per tasks.md T283: library search MUST route through the FTS SearchService
// so it matches todo text, code-block text, file display names, and
// screenshot captions (FR-023) and is NOT bounded by the 500-card row limit
// (SC-005). Privacy-excluded notes are never revealed (T042).

@MainActor
@Suite struct SearchWiringTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000004")!

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
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.search.\(UUID().uuidString)") ?? .standard)
        )
    }

    /// Creates a note with a single block of the given kind/payload and
    /// reindexes the FTS document the way the save path does (T281/T283).
    @discardableResult
    private func createNote(
        environment: AppEnvironment,
        title: String? = nil,
        blocks: [Block]
    ) async throws -> UUID {
        let repo = environment.persistence.noteRepository!
        let note = Note(title: title, lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)
        for block in blocks {
            var fixed = block
            fixed = Block(
                id: block.id,
                noteId: note.id,
                kind: block.kind,
                sortKey: block.sortKey,
                payload: block.payload,
                versionId: block.versionId,
                parentVersionId: block.parentVersionId,
                lastModifiedDeviceId: block.lastModifiedDeviceId,
                createdAt: block.createdAt,
                modifiedAt: block.modifiedAt
            )
            try await repo.insert(fixed)
        }
        if let service = environment.persistence.searchService {
            let stored = try await repo.fetchBlocks(noteId: note.id)
            try await service.reindexNote(noteId: note.id, title: title, blocks: stored)
        }
        return note.id
    }

    private func todoBlock(noteId: UUID, text: String) -> Block {
        Block(
            noteId: noteId,
            kind: .todo,
            sortKey: 0,
            payload: .todo(TodoPayload(todoId: UUID(), richText: RichTextDocument(text: text, paragraphs: []))),
            lastModifiedDeviceId: Self.deviceId
        )
    }

    @Test
    func searchMatchesTodoCodeFilenameAndCaption() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        let repo = env.persistence.noteRepository!

        let noteA = Note(title: "Grocery List", lastModifiedDeviceId: Self.deviceId)
        try await repo.create(noteA)
        let blockA = todoBlock(noteId: noteA.id, text: "buy avocados")
        try await repo.insert(blockA)
        if let service = env.persistence.searchService {
            try await service.reindexNote(noteId: noteA.id, title: "Grocery List", blocks: [blockA])
        }

        let noteB = Note(title: "Meeting Notes", lastModifiedDeviceId: Self.deviceId)
        try await repo.create(noteB)
        let codeBlock = Block(
            noteId: noteB.id,
            kind: .code,
            sortKey: 0,
            payload: .code(.init(text: "let secretAPIKey = 42", language: "swift")),
            lastModifiedDeviceId: Self.deviceId
        )
        try await repo.insert(codeBlock)
        if let service = env.persistence.searchService {
            try await service.reindexNote(noteId: noteB.id, title: "Meeting Notes", blocks: [codeBlock])
        }

        // FR-023: search matches TODO text.
        model.searchQuery = "avocados"
        await model.reload()
        #expect(model.cards.contains { $0.noteId == noteA.id }, "todo text is searchable (FR-023)")
        #expect(!model.cards.isEmpty)

        // FR-023: search matches CODE-block text.
        model.searchQuery = "secretAPIKey"
        await model.reload()
        #expect(model.cards.contains { $0.noteId == noteB.id }, "code-block text is searchable (FR-023)")
    }

    @Test
    func searchIsNotBoundedByCardLimit() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        let repo = env.persistence.noteRepository!

        // Create 505 notes; only the LAST one matches the query. FTS search
        // must find it even though CardProjection.maxRows == 500.
        var matchId: UUID?
        for index in 0..<505 {
            let title = index == 504 ? "needle-q7x9 unique-title" : "filler note \(index)"
            let note = Note(title: title, lastModifiedDeviceId: Self.deviceId)
            try await repo.create(note)
            if index == 504 { matchId = note.id }
        }
        #expect(matchId != nil)

        model.searchQuery = "needle-q7x9"
        await model.reload()
        #expect(model.cards.contains { $0.noteId == matchId }, "a match beyond the 500-card bound appears (SC-005)")
    }

    @Test
    func searchNeverRevealsPrivacyExcludedNotes() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        let repo = env.persistence.noteRepository!

        let visible = Note(title: "public note", widgetEligible: true, lastModifiedDeviceId: Self.deviceId)
        try await repo.create(visible)
        if let svc = env.persistence.searchService {
            try await svc.reindexNote(noteId: visible.id, title: "public note", blocks: [])
        }
        let excluded = Note(title: "private note", widgetEligible: false, lastModifiedDeviceId: Self.deviceId)
        try await repo.create(excluded)
        if let svc = env.persistence.searchService {
            try await svc.reindexNote(noteId: excluded.id, title: "private note", blocks: [])
        }

        model.searchQuery = "note"
        await model.reload()
        #expect(model.cards.contains { $0.noteId == visible.id })
        #expect(!model.cards.contains { $0.noteId == excluded.id }, "privacy-excluded notes are never revealed (T042)")
    }
}
