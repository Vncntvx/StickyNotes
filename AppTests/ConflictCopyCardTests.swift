import Testing
import Foundation
import Domain
import Persistence
@testable import StickyNotes

// MARK: - R2.1 conflict-copy card visibility + label (remediation Phase 2)
//
// FR-175: conflict copies are visible in the library (distinguishable,
// labeled) — NoteLifecycle.libraryVisibleStates == [.active, .conflictCopy].
// The library previously fetched ONLY active notes, so conflict copies were
// invisible AND the ConflictCopyBadge component was dead code (audit D-1).

@MainActor
@Suite struct ConflictCopyCardTests {

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return AppEnvironment(
            persistence: PersistenceServices(store: store),
            assets: AssetServices(),
        )
    }

    /// Inserts a conflict-copy note directly (the repository only creates
    /// active notes; conflict copies come from sync recovery).
    private func insertConflictCopyNote(
        store: DatabaseStore,
        noteId: UUID,
        label: String
    ) async throws {
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, colorKey, transparency, textSize, alwaysOnTop,
                                      manualSortKey, lifecycleState, conflictOriginNoteId, conflictLabel,
                                      versionId, lastModifiedDeviceId, createdAt, modifiedAt)
                    VALUES (?, 'yellow', 1.0, 13, 0, 0, 'conflictCopy', ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    noteId.uuidString,
                    UUID().uuidString,
                    label,
                    UUID().uuidString,
                    UUID().uuidString,
                    Date().timeIntervalSince1970,
                    Date().timeIntervalSince1970,
                ]
            )
        }
    }

    @Test
    func conflictCopyAppearsInLibraryWithLabel() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        let noteId = UUID()
        let label = "conflict-copy-2026-08-15T00:00:00Z-abcdef12"
        try await insertConflictCopyNote(store: env.persistence.store!, noteId: noteId, label: label)

        await model.reload()
        #expect(model.cards.contains { $0.noteId == noteId },
                "conflict copies must be visible in the library (FR-175, libraryVisibleStates)")
        let card = model.cards.first { $0.noteId == noteId }
        #expect(card?.isConflictCopy == true)
        #expect(card?.conflictLabel == label, "the conflict label must reach the card row")
    }

    @Test
    func conflictCopySearchableViaFTS() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        let noteId = UUID()
        try await insertConflictCopyNote(store: env.persistence.store!, noteId: noteId, label: "conflict-copy-abc")
        // Seed an FTS content row for the conflict copy.
        let fts = FullTextSearch(dbPool: env.persistence.store!.dbPool)
        try await fts.upsertSearchDocument(SearchDocument(
            noteId: noteId,
            title: "Recovered note",
            summary: "", body: "conflict content", todos: "", code: "",
            fileNames: "", captions: "", ocr: ""
        ))

        model.setSearchQuery("conflict")
        await model.reload()
        #expect(model.cards.contains { $0.noteId == noteId },
                "conflict copies must be searchable in the library (FR-023 scope)")
    }
}
