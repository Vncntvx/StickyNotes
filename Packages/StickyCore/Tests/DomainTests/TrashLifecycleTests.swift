import Testing
import Foundation
import Domain

// MARK: - NoteLifecycle + Trash lifecycle tests (T076)
//
// Per tasks.md T076: "Domain test: lifecycle transitions active→trashed→
// permanentlyDeleted; 30-day expiry; distinguish Trash/permanent/
// conflictCopy/active."

@Suite struct TrashLifecycleTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    // MARK: - Legal transitions

    @Test
    func activeToTrashIsLegal() {
        #expect(NoteLifecycle.canTransition(from: .active, .trash))
        let result = NoteLifecycle.apply(.trash, to: .active, now: Date(timeIntervalSince1970: 1_000))!
        #expect(result.state == .trashed)
        #expect(result.trashedAt != nil)
    }

    @Test
    func trashedToRestoreIsLegal() {
        #expect(NoteLifecycle.canTransition(from: .trashed, .restore))
        let result = NoteLifecycle.apply(.restore, to: .trashed)!
        #expect(result.state == .active)
        #expect(result.trashedAt == nil)
    }

    @Test
    func trashedToPermanentlyDeletedIsLegal() {
        #expect(NoteLifecycle.canTransition(from: .trashed, .permanentlyDelete))
        let result = NoteLifecycle.apply(.permanentlyDelete, to: .trashed)!
        #expect(result.state == .permanentlyDeleted)
        #expect(result.trashedAt == nil)
    }

    @Test
    func anyStateToConflictCopyIsLegal() {
        // Sync recovery can mark any note as a conflict copy (e.g., a delete
        // vs edit conflict recovers the edited side as a conflict copy).
        #expect(NoteLifecycle.canTransition(from: .active, .markConflictCopy))
        #expect(NoteLifecycle.canTransition(from: .trashed, .markConflictCopy))
        #expect(NoteLifecycle.canTransition(from: .permanentlyDeleted, .markConflictCopy))
        #expect(NoteLifecycle.canTransition(from: .conflictCopy, .markConflictCopy))
    }

    // MARK: - Illegal transitions

    @Test
    func illegalTransitionsRejected() {
        // Can't trash a trashed note (already trashed).
        #expect(!NoteLifecycle.canTransition(from: .trashed, .trash))
        // Can't restore an active note (not trashed).
        #expect(!NoteLifecycle.canTransition(from: .active, .restore))
        // Can't permanently delete an active note directly (must trash first).
        #expect(!NoteLifecycle.canTransition(from: .active, .permanentlyDelete))
        // Can't permanently delete an already-permanently-deleted note.
        #expect(!NoteLifecycle.canTransition(from: .permanentlyDeleted, .permanentlyDelete))
    }

    @Test
    func applyIllegalTransitionReturnsNil() {
        #expect(NoteLifecycle.apply(.restore, to: .active) == nil)
        #expect(NoteLifecycle.apply(.permanentlyDelete, to: .active) == nil)
    }

    // MARK: - 30-day expiry

    @Test
    func noteWithin30DaysIsNotEligibleForPurge() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let trashed = now.addingTimeInterval(-29 * 24 * 60 * 60)  // 29 days ago
        #expect(!NoteLifecycle.isEligibleForPurge(trashedAt: trashed, now: now))
    }

    @Test
    func noteAtExactly30DaysIsEligibleForPurge() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let trashed = now.addingTimeInterval(-30 * 24 * 60 * 60)  // exactly 30 days
        #expect(NoteLifecycle.isEligibleForPurge(trashedAt: trashed, now: now))
    }

    @Test
    func noteBeyond30DaysIsEligibleForPurge() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let trashed = now.addingTimeInterval(-60 * 24 * 60 * 60)  // 60 days ago
        #expect(NoteLifecycle.isEligibleForPurge(trashedAt: trashed, now: now))
    }

    // MARK: - Trash expiry scan

    @Test
    func expiryScanFindsEligibleNotes() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let trashed = [
            (id: UUID(), trashedAt: now.addingTimeInterval(-10 * 24 * 60 * 60)),  // 10 days — keep
            (id: UUID(), trashedAt: now.addingTimeInterval(-29 * 24 * 60 * 60)),  // 29 days — keep
            (id: UUID(), trashedAt: now.addingTimeInterval(-30 * 24 * 60 * 60)),  // 30 days — purge
            (id: UUID(), trashedAt: now.addingTimeInterval(-90 * 24 * 60 * 60)),  // 90 days — purge
        ]
        let eligible = TrashExpiry.notesEligibleForPurge(trashedNotes: trashed, now: now)
        #expect(eligible.count == 2)
        #expect(eligible.contains(trashed[2].id))
        #expect(eligible.contains(trashed[3].id))
    }

    // MARK: - Distinguishability (FR-014 / T125)

    @Test
    func lifecycleStatesAreDistinguishable() {
        let labels = Set([
            NoteLifecycle.distinguishabilityLabel(for: .active),
            NoteLifecycle.distinguishabilityLabel(for: .trashed),
            NoteLifecycle.distinguishabilityLabel(for: .permanentlyDeleted),
            NoteLifecycle.distinguishabilityLabel(for: .conflictCopy),
        ])
        #expect(labels.count == 4, "all four lifecycle states must have distinct labels")
    }

    @Test
    func libraryVisibleStatesAreActiveAndConflictCopy() {
        let visible = Set(NoteLifecycle.libraryVisibleStates)
        #expect(visible == [.active, .conflictCopy])
    }

    @Test
    func trashVisibleStatesIsTrashedOnly() {
        let visible = Set(NoteLifecycle.trashVisibleStates)
        #expect(visible == [.trashed])
    }
}
