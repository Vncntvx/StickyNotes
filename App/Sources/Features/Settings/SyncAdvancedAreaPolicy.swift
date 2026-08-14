import Foundation

// MARK: - SyncAdvancedAreaPolicy (003 T057/T186, FR-054/SC-013/FR-163; Rev 3 2026-08-14)
//
// Per tasks.md T057 + T186 and spec FR-054 (Rev 3): the ADVANCED area holds
// the technical operations only (exports + Vault ID); vault/storage
// management (Join Another Vault… / Set Up New Storage Location…) lives in
// the Storage section's "Manage…" menu — separate actions, never merged
// into one flow (join stays its own product action, CHK033 re-entry
// preserved); Disconnect Sync… is a standalone destructive entry at the
// bottom of the pane (confirmed, role: .destructive); the
// unrecoverable-password warning is concise standard style and its info
// row lives in the Security section (FR-163). Asserted by T054 + T175.

public enum SyncAdvancedAreaPolicy {
    /// SC-013: maintenance ops are separated from the primary sync page.
    public static let operationsInSeparateAdvancedArea = true
    /// Rev 3: the Advanced-area operations — the technical subset only.
    public static let operations = [
        "Export Sync Profile",
        "Export Diagnostic Bundle",
    ]
    /// Rev 3: vault/storage management lives in the Storage "Manage…" menu
    /// (still separate actions — join ≠ change-storage-location).
    public static let managedOperationsInStorageSection = true
    public static let managedOperationNames = [
        "Join Another Vault",
        "Set Up New Storage Location",
    ]
    /// Rev 3: Disconnect Sync… is a standalone destructive entry.
    public static let disconnectIsStandaloneDestructiveEntry = true
    /// CHK033: join has both paths (initial setup + re-entry).
    public static let initialSetupJoinEnabled = true
    public static let recoveryReEntryEnabled = true
    /// Rev 2/3: join is its own product action — never merged into the
    /// storage-location change flow.
    public static let joinIsSeparateProductAction = true
    /// FR-154: destructive ops are confirmed + visually distinct.
    public static let destructiveOperationsConfirmed = true
    public static let destructiveVisuallyDistinct = true
    /// FR-163: the unrecoverable warning is concise standard style; its
    /// info row lives in the Security section (Rev 3), not an always-on
    /// orange warning.
    public static let warningIsConciseStandard = true
    public static let stableStateShowsRecoveryInfoRow = true
    public static let recoveryRowInSecuritySection = true
}
