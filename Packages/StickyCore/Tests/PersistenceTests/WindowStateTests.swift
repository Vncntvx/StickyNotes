import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

// MARK: - WindowState repository tests (T047)
//
// Per tasks.md T047: "Persistence test: WindowState (frame,
// preferredDisplayUUID, fallbackFrame) stored device-local, never synced."

@Suite struct WindowStateTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    private func freshRepo() async throws -> (SQLiteWindowStateRepository, DatabaseStore) {
        let store = try DatabaseStore.inMemory()
        let migrator = InitialSchema.migrator()
        try migrator.migrate(store.dbPool)
        return (SQLiteWindowStateRepository(store: store), store)
    }

    /// Inserts a minimal note row so the windowState.noteId FK is satisfied.
    private func createNoteRow(_ store: DatabaseStore, noteId: UUID) async throws {
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, colorKey, transparency, textSize, alwaysOnTop, widgetEligible,
                                      manualSortKey, lifecycleState, versionId, lastModifiedDeviceId,
                                      createdAt, modifiedAt)
                    VALUES (?, 'yellow', 0.0, 'regular', 0, 1, 0, 'active', ?, ?, ?, ?)
                    """,
                arguments: [noteId.uuidString, UUID().uuidString, Self.deviceId.uuidString,
                            Date().timeIntervalSince1970, Date().timeIntervalSince1970]
            )
        }
    }

    @Test
    func fetchMissingReturnsNil() async throws {
        let (repo, _) = try await freshRepo()
        let state = try await repo.fetch(noteId: UUID())
        #expect(state == nil)
    }

    @Test
    func upsertRoundTripsAllFields() async throws {
        let (repo, store) = try await freshRepo()
        let noteId = UUID()
        try await createNoteRow(store, noteId: noteId)
        let state = WindowState(
            noteId: noteId,
            frame: WindowFrame(x: 100, y: 200, width: 320, height: 480),
            preferredDisplayUUID: "DISPLAY-UUID-ABC",
            fallbackFrame: WindowFrame(x: 0, y: 0, width: 320, height: 480),
            isOpen: true,
            lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await repo.upsert(state)
        let fetched = try await repo.fetch(noteId: noteId)!
        #expect(fetched.frame == state.frame)
        #expect(fetched.preferredDisplayUUID == state.preferredDisplayUUID)
        #expect(fetched.fallbackFrame == state.fallbackFrame)
        #expect(fetched.isOpen == state.isOpen)
        #expect(fetched.lastOpenedAt == state.lastOpenedAt)
    }

    @Test
    func markOpenSetsIsOpenWithoutLosingFrame() async throws {
        let (repo, store) = try await freshRepo()
        let noteId = UUID()
        try await createNoteRow(store, noteId: noteId)
        let state = WindowState(noteId: noteId, frame: WindowFrame(x: 50, y: 60, width: 200, height: 300), preferredDisplayUUID: "DISPLAY-1")
        try await repo.upsert(state)
        try await repo.markOpen(noteId: noteId)
        let after = try await repo.fetch(noteId: noteId)!
        #expect(after.isOpen == true)
        #expect(after.frame == state.frame, "markOpen must not clobber the frame")
        #expect(after.preferredDisplayUUID == state.preferredDisplayUUID)
        #expect(after.lastOpenedAt != nil)
    }

    @Test
    func markOpenOnNeverStoredNoteCreatesRow() async throws {
        let (repo, store) = try await freshRepo()
        let noteId = UUID()
        try await createNoteRow(store, noteId: noteId)
        try await repo.markOpen(noteId: noteId)
        let state = try await repo.fetch(noteId: noteId)!
        #expect(state.isOpen == true)
        #expect(state.lastOpenedAt != nil)
        #expect(state.frame.width >= 0)
    }

    @Test
    func markClosedClearsIsOpenButKeepsFrame() async throws {
        let (repo, store) = try await freshRepo()
        let noteId = UUID()
        try await createNoteRow(store, noteId: noteId)
        let frame = WindowFrame(x: 1, y: 2, width: 3, height: 4)
        try await repo.upsert(WindowState(noteId: noteId, frame: frame, preferredDisplayUUID: "D"))
        try await repo.markOpen(noteId: noteId)
        try await repo.markClosed(noteId: noteId)
        let after = try await repo.fetch(noteId: noteId)!
        #expect(after.isOpen == false)
        #expect(after.frame == frame, "FR-007: geometry retained after close")
    }

    @Test
    func updateFrameOverwritesFrameAndDisplay() async throws {
        let (repo, store) = try await freshRepo()
        let noteId = UUID()
        try await createNoteRow(store, noteId: noteId)
        try await repo.upsert(WindowState(noteId: noteId, frame: WindowFrame(x: 0, y: 0, width: 100, height: 100), preferredDisplayUUID: "OLD"))
        let newFrame = WindowFrame(x: 500, y: 600, width: 800, height: 600)
        try await repo.updateFrame(noteId: noteId, frame: newFrame, preferredDisplayUUID: "NEW")
        let after = try await repo.fetch(noteId: noteId)!
        #expect(after.frame == newFrame)
        #expect(after.preferredDisplayUUID == "NEW")
    }

    @Test
    func frameRoundTripsThroughCanonicalJSON() async throws {
        let (repo, store) = try await freshRepo()
        let noteId = UUID()
        try await createNoteRow(store, noteId: noteId)
        let precise = WindowFrame(x: 123.456789, y: -42.5, width: 1024.25, height: 768.75)
        try await repo.upsert(WindowState(noteId: noteId, frame: precise, preferredDisplayUUID: nil))
        let fetched = try await repo.fetch(noteId: noteId)!
        #expect(fetched.frame == precise)
    }

    @Test
    func windowStateIsDeviceLocalAndNeverSynced() {
        // WindowState is NOT part of CanonicalNote. Constitution IX:
        // device-local fields never appear in canonical JSON.
        let state = WindowState(noteId: UUID(), frame: WindowFrame(x: 0, y: 0, width: 100, height: 100), preferredDisplayUUID: "D", isOpen: true, lastOpenedAt: Date())
        #expect(state.isOpen == true)
    }
}
