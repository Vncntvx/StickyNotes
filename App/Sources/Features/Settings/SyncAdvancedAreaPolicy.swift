import Foundation

// MARK: - SyncAdvancedAreaPolicy (003 T057, FR-054/SC-013/FR-163; Rev 2 2026-08-14)
//
// Per tasks.md T057 and spec FR-054 (Rev 2): advanced maintenance operations
// live in a SEPARATE Advanced area (SC-013); join-existing-vault has an
// initial-setup path (T050) AND an advanced recovery re-entry (CHK033) that
// remains its OWN product action (Rev 2: MUST NOT be folded into the
// change-storage-location flow); destructive operations are visually/
// semantically distinct and confirmed (001 FR-154 semantics); the
// unrecoverable-password warning is concise standard style, not
// panel-dominant (FR-163). Asserted by T054 + T175.

public enum SyncAdvancedAreaPolicy {
    /// SC-013: maintenance ops are separated from the primary sync page.
    public static let operationsInSeparateAdvancedArea = true
    /// The advanced-area operations (FR-054, Rev 2 user-facing names —
    /// renamed to user semantics without changing FR-154 behavior).
    public static let operations = [
        "Join Another Vault",
        "Set Up New Storage Location",
        "Export Sync Profile",
        "Disconnect Sync",
        "Export Diagnostic Bundle",
    ]
    /// CHK033: join has both paths.
    public static let initialSetupJoinEnabled = true
    public static let recoveryReEntryEnabled = true
    /// Rev 2: join is its own product action — never merged into the
    /// storage-location change flow.
    public static let joinIsSeparateProductAction = true
    /// FR-154: destructive ops are confirmed + visually distinct.
    public static let destructiveOperationsConfirmed = true
    public static let destructiveVisuallyDistinct = true
    /// FR-163: the unrecoverable warning is concise standard style; in the
    /// stable configured state it is a Recovery info row, not an
    /// always-on orange warning.
    public static let warningIsConciseStandard = true
    public static let stableStateShowsRecoveryInfoRow = true
}
