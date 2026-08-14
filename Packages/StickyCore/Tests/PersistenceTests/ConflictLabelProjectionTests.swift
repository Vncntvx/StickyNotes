import Testing
import Foundation
import Domain
import Persistence

// MARK: - R2.1 conflict-copy card label (remediation Phase 2)
//
// FR-175 distinguishability: a conflict copy's `conflictLabel` must flow
// through the card projection so the library can render the labeled badge
// (ConflictCopyBadge). The projection previously carried only the
// `isConflictCopy` boolean — the label was dropped (audit D-1: the
// ConflictCopyView component was never wired).

@Suite struct ConflictLabelProjectionTests {

    private func freshDatabase() async throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    @Test
    func conflictCopyLabelFlowsThroughCardProjection() async throws {
        let store = try await freshDatabase()
        let noteId = UUID()
        let deviceId = UUID()
        let label = "conflict-copy-2026-08-15T00:00:00Z-abcdef12"

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
                    deviceId.uuidString,
                    Date().timeIntervalSince1970,
                    Date().timeIntervalSince1970,
                ]
            )
        }

        let cards = try await CardProjection.fetchCardProjections(
            store: store,
            lifecycle: .conflictCopy,
            sort: .modified
        )
        #expect(cards.count == 1, "the conflict copy must be visible in the conflictCopy scope")
        #expect(cards.first?.noteId == noteId)
        #expect(cards.first?.isConflictCopy == true)
        #expect(cards.first?.conflictLabel == label,
                "the conflict label must flow through the card projection (FR-175)")
    }

    @Test
    func activeNoteHasNoConflictLabel() async throws {
        let store = try await freshDatabase()
        let noteId = UUID()
        let deviceId = UUID()
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, colorKey, transparency, textSize, alwaysOnTop,
                                      manualSortKey, lifecycleState,
                                      versionId, lastModifiedDeviceId, createdAt, modifiedAt)
                    VALUES (?, 'yellow', 1.0, 13, 0, 0, 'active', ?, ?, ?, ?)
                    """,
                arguments: [
                    noteId.uuidString,
                    UUID().uuidString,
                    deviceId.uuidString,
                    Date().timeIntervalSince1970,
                    Date().timeIntervalSince1970,
                ]
            )
        }
        let cards = try await CardProjection.fetchCardProjections(
            store: store,
            lifecycle: .active,
            sort: .modified
        )
        #expect(cards.first?.conflictLabel == nil, "active notes carry no conflict label")
        #expect(cards.first?.isConflictCopy == false)
    }
}
