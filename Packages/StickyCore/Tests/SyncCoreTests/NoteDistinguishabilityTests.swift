import Testing
import Foundation
import Domain
import Persistence
import SecurityCore
import SyncCore

// MARK: - Note distinguishability tests (T163o / T125, US10)
//
// Per tasks.md T163o: "distinguish Trash/permanent-deleted/recovered-conflict-
// copy/active".

@Suite struct NoteDistinguishabilityTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    @Test
    func fourLifecycleStatesAreDistinct() {
        let active = Note(lifecycleState: .active, lastModifiedDeviceId: Self.deviceId)
        let trashed = Note(lifecycleState: .trashed, lastModifiedDeviceId: Self.deviceId)
        let deleted = Note(lifecycleState: .permanentlyDeleted, lastModifiedDeviceId: Self.deviceId)
        let conflict = Note(lifecycleState: .conflictCopy, lastModifiedDeviceId: Self.deviceId)

        let states = Set([active.lifecycleState, trashed.lifecycleState, deleted.lifecycleState, conflict.lifecycleState])
        #expect(states.count == 4, "all four states must be distinguishable")

        #expect(active.lifecycleState == .active)
        #expect(trashed.lifecycleState == .trashed)
        #expect(deleted.lifecycleState == .permanentlyDeleted)
        #expect(conflict.lifecycleState == .conflictCopy)
    }

    @Test
    func conflictCopyCarriesOriginIdentity() {
        let originalId = UUID()
        let conflict = Note(
            lifecycleState: .conflictCopy,
            conflictOriginNoteId: originalId,
            conflictLabel: "conflict-copy-2026-08-07",
            lastModifiedDeviceId: Self.deviceId
        )
        #expect(conflict.conflictOriginNoteId == originalId)
        #expect(conflict.conflictLabel != nil)
        #expect(conflict.lifecycleState == .conflictCopy)

        let active = Note(lifecycleState: .active, lastModifiedDeviceId: Self.deviceId)
        #expect(active.conflictOriginNoteId == nil)
        #expect(active.conflictLabel == nil)
    }

    @Test
    func trashedNotesCarryTrashTimestamp() {
        let trashed = Note(lifecycleState: .trashed, trashedAt: Date(), lastModifiedDeviceId: Self.deviceId)
        #expect(trashed.trashedAt != nil)
        let active = Note(lifecycleState: .active, lastModifiedDeviceId: Self.deviceId)
        #expect(active.trashedAt == nil)
    }

    @Test
    func permanentlyDeletedCarriesNoReadableState() {
        let deleted = Note(lifecycleState: .permanentlyDeleted, lastModifiedDeviceId: Self.deviceId)
        // Distinguishable from a conflict copy by lifecycle alone.
        #expect(deleted.lifecycleState != .conflictCopy)
        #expect(deleted.lifecycleState != .active)
        #expect(deleted.lifecycleState != .trashed)
    }
}
