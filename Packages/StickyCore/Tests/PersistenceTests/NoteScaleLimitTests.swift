import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

// MARK: - Note scale-limit tests (T227, FR-090b — persistence side)
//
// The asset-side limits live in AssetStoreTests/ScaleLimitTests.swift. This
// file covers the note structured-content cap (5 MB): a content change that
// would push a note's canonical envelope past 5 MB is refused while the
// last valid saved state is preserved intact.

@Suite struct NoteScaleLimitTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    private func freshRepo() async throws -> (SQLiteNoteRepository, DatabaseStore) {
        let store = try DatabaseStore.inMemory()
        let migrator = InitialSchema.migrator()
        try migrator.migrate(store.dbPool)
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        return (repo, store)
    }

    @Test
    func oversizeNoteContentRefusedWhileLastStatePreserved() async throws {
        let (repo, _) = try await freshRepo()
        let note = Note(title: "Big", lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        // A small block first (the last valid saved state).
        try await repo.insert(Block(
            noteId: note.id,
            kind: .richText,
            sortKey: 0,
            payload: .richText(.plain("small")),
            lastModifiedDeviceId: Self.deviceId
        ))

        // A block that pushes content past 5 MB: the write is refused.
        let huge = String(repeating: "x", count: ScaleLimits.maxNoteContentBytes)
        do {
            try await repo.insert(Block(
                noteId: note.id,
                kind: .code,
                sortKey: 1024,
                payload: .code(CodePayload(text: huge)),
                lastModifiedDeviceId: Self.deviceId
            ))
            Issue.record("oversize content write must be refused")
        } catch let error as StickyError {
            guard case .persistence(.contentTooLarge) = error else {
                Issue.record("wrong error: \(error.sanitizedCode)")
                return
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }

        // The last valid saved state is preserved intact.
        let blocks = try await repo.fetchBlocks(noteId: note.id)
        #expect(blocks.count == 1)
        #expect(blocks.first?.kind == .richText)
        if case .richText(let doc) = blocks.first?.payload {
            #expect(doc.text == "small")
        } else {
            Issue.record("last valid state must be preserved")
        }
    }

    @Test
    func validationHelperRefusesOversizeNote() async throws {
        let (repo, store) = try await freshRepo()
        let note = Note(title: "Big", lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        // Insert the oversized payload via raw SQL (bypassing the repo's own
        // insert-time enforcement) so the validator is exercised directly.
        let huge = String(repeating: "y", count: ScaleLimits.maxNoteContentBytes)
        let payloadJSON = String(data: try CanonicalJSONEncoder().encode(
            CanonicalBlockPayload.code(CodePayload(text: huge))
        ), encoding: .utf8)!
        let blockId = UUID()
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO block (id, noteId, kind, sortKey, payload, versionId, lastModifiedDeviceId, createdAt, modifiedAt)
                    VALUES (?, ?, 'code', 0, ?, ?, ?, ?, ?)
                    """,
                arguments: [blockId.uuidString, note.id.uuidString, payloadJSON, UUID().uuidString,
                            Self.deviceId.uuidString, Date(), Date()]
            )
        }

        do {
            try await repo.validateNoteContentSize(noteId: note.id)
            Issue.record("validateNoteContentSize must throw for oversize content")
        } catch let error as StickyError {
            guard case .persistence(.contentTooLarge) = error else {
                Issue.record("wrong error: \(error.sanitizedCode)")
                return
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }
}
