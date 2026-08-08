import Testing
import Foundation
@testable import StickyNotes

// MARK: - Deletion confirmation tests (003 T017, FR-026/CHK013)
//
// Per tasks.md T017 and spec FR-026: move-to-Trash needs NO confirmation
// (001 FR-014 unchanged); permanent delete (single note) and empty Trash
// require EXPLICIT confirmation with permanent-deletion wording including
// the "30 天可恢复保证不再适用" clause (CHK013). Confirmation requirements
// live in `DeletionConfirmationPolicy` (the single source the Trash
// destination UI uses), so they are testable deterministically.

@Suite struct DeletionConfirmationTests {

    @Test
    func moveToTrashRequiresNoConfirmation() {
        // FR-026: moving to Trash is reversible (30-day recovery) — no
        // confirmation.
        #expect(DeletionConfirmationPolicy.confirmation(for: .moveToTrash) == nil,
                "move-to-Trash must never require confirmation (001 FR-014)")
    }

    @Test
    func permanentDeleteRequiresExplicitConfirmation() {
        let requirement = DeletionConfirmationPolicy.confirmation(for: .permanentDeleteSingle)
        #expect(requirement != nil, "single permanent delete MUST be confirmed (FR-026)")
        #expect(requirement?.isDestructive == true, "permanent delete is destructive")
    }

    @Test
    func emptyTrashRequiresExplicitConfirmation() {
        let requirement = DeletionConfirmationPolicy.confirmation(for: .emptyTrash)
        #expect(requirement != nil, "empty Trash MUST be confirmed (FR-014b/FR-026)")
        #expect(requirement?.isDestructive == true)
    }

    @Test
    func confirmationWordingIncludesThirtyDayGuaranteeClause() {
        // CHK013: permanent deletion wording must state that the 30-day
        // recoverability guarantee no longer applies.
        for action in [DeletionConfirmationPolicy.DeletionAction.permanentDeleteSingle,
                       DeletionConfirmationPolicy.DeletionAction.emptyTrash] {
            let wording = DeletionConfirmationPolicy.confirmation(for: action)?.message ?? ""
            #expect(
                wording.localizedCaseInsensitiveContains("30-day") ||
                wording.localizedCaseInsensitiveContains("30 天"),
                "confirmation must mention the 30-day guarantee loss (got: \(wording))"
            )
        }
    }

    @Test
    func confirmationWordingHasNoInternalIdentifiers() {
        // FR-011/SC-012: user-facing wording never leaks internal codes.
        for action in DeletionConfirmationPolicy.DeletionAction.allCases {
            if let requirement = DeletionConfirmationPolicy.confirmation(for: action) {
                #expect(!requirement.message.contains("sync."), "no internal error identifiers")
                #expect(!requirement.message.contains("ProviderError"), "no internal type names")
                #expect(!requirement.message.contains("https://"), "no URLs")
            }
        }
    }
}
