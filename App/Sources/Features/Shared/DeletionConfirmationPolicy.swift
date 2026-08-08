import Foundation

// MARK: - DeletionConfirmationPolicy (003 T023, FR-026/CHK013)
//
// Per tasks.md T023/T017 and spec FR-026: the Trash destination's
// destructive actions require EXPLICIT confirmation with permanent-
// deletion wording (including the 30-day guarantee loss clause, CHK013);
// move-to-Trash never confirms (001 FR-014 — reversible within 30 days).
// This policy is the single source of confirmation requirements; the UI
// (card context menu, Empty Trash) consults it, and DeletionConfirmationTests
// (T017) assert it deterministically.

public enum DeletionConfirmationPolicy {

    /// The user-facing deletion actions that may need confirmation.
    public enum DeletionAction: CaseIterable, Sendable {
        /// Move to Trash (reversible — NO confirmation).
        case moveToTrash
        /// Permanently delete a single note (beyond Trash recovery).
        case permanentDeleteSingle
        /// Empty Trash (batch permanent delete).
        case emptyTrash
    }

    /// A confirmation requirement: the message shown and whether the
    /// action is destructive (visually/semantically distinct — 001
    /// FR-154 semantics).
    public struct ConfirmationRequirement: Equatable, Sendable {
        public let message: String
        public let isDestructive: Bool

        public init(message: String, isDestructive: Bool = true) {
            self.message = message
            self.isDestructive = isDestructive
        }
    }

    /// The 30-day recoverability clause (CHK013) — stated in permanent-
    /// deletion confirmations.
    public static let thirtyDayClause = String(localized: "The 30-day recoverability guarantee no longer applies.")

    /// Returns the confirmation requirement for an action, or nil when no
    /// confirmation is required (move-to-Trash).
    public static func confirmation(for action: DeletionAction) -> ConfirmationRequirement? {
        switch action {
        case .moveToTrash:
            // FR-026: reversible within 30 days — never confirm.
            return nil
        case .permanentDeleteSingle:
            return ConfirmationRequirement(
                message: "This note will be permanently deleted immediately. " + thirtyDayClause
            )
        case .emptyTrash:
            return ConfirmationRequirement(
                message: "All notes in Trash will be permanently deleted immediately. " + thirtyDayClause
            )
        }
    }
}
