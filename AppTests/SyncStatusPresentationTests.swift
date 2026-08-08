import Testing
import Foundation
import Domain
import SyncCore
@testable import StickyNotes

// MARK: - Sync status presentation tests (003 T051, FR-012/SC-012/CHK002)
//
// Per tasks.md T051 and spec FR-012: every internal error category maps
// deterministically to ONE of the seven user-facing categories
// (cannotConnect/authFailed/needsUnlock/pendingChanges/
// conflictCopiesCreated/historyAgedOut/repositoryDamaged); zh-Hans/en
// strings complete; NO internal identifiers in user-facing text
// (FR-011/SC-012); MULTI-category priority resolution is deterministic
// (CHK002 — plan.md §9: ⑦>③>②>①>⑤>④>⑥).

@Suite struct SyncStatusPresentationTests {

    private static func presentation(
        state: SyncStatusInput = .init(),
        summary: SyncSummary = .empty
    ) -> SyncStatusPresentation? {
        SyncStatusResolver.resolve(
            isConfigured: state.isConfigured,
            lastError: state.lastError,
            vaultLocked: state.vaultLocked,
            hasOfflineChangesPending: state.hasOfflineChangesPending,
            summary: summary
        )
    }

    @Test
    func idleSyncHasZeroFootprint() {
        // FR-007: idle/configured/synced → no banner at all.
        #expect(SyncStatusResolver.resolve(
            isConfigured: true,
            lastError: nil,
            vaultLocked: false,
            hasOfflineChangesPending: false,
            summary: .empty
        ) == nil, "normal sync state renders nothing (zero footprint)")
    }

    // MARK: - Exhaustive single-category mapping

    @Test
    func transientProviderErrorMapsToCannotConnect() {
        for transient in [ProviderError.network, .server, .conflict, .clockSkew] {
            let result = Self.presentation(state: .init(lastError: transient))
            #expect(result?.category == .cannotConnect,
                    "\(transient.sanitizedCode) → cannotConnect (①)")
            #expect(result?.action == .retry)
        }
    }

    @Test
    func authErrorsMapToAuthFailed() {
        for auth in [ProviderError.auth, .forbidden] {
            let result = Self.presentation(state: .init(lastError: auth))
            #expect(result?.category == .authFailed,
                    "\(auth.sanitizedCode) → authFailed (②)")
            #expect(result?.action == .reauthenticate)
        }
    }

    @Test
    func vaultLockedMapsToNeedsUnlock() {
        let result = Self.presentation(state: .init(vaultLocked: true))
        #expect(result?.category == .needsUnlock, "vault locked → needsUnlock (③)")
        #expect(result?.action == .unlock)
    }

    @Test
    func offlineChangesPendingMapsToPendingChanges() {
        let result = Self.presentation(state: .init(hasOfflineChangesPending: true))
        #expect(result?.category == .pendingChanges, "offline changes → pendingChanges (④)")
    }

    @Test
    func conflictCopiesMapToConflictCopiesCreated() {
        let result = Self.presentation(state: .init(), summary: SyncSummary(conflictCopiesCreated: 2))
        #expect(result?.category == .conflictCopiesCreated, "conflict copies → ⑤")
        #expect(result?.action == .viewConflicts)
    }

    @Test
    func historyAgedOutMapsToHistoryAgedOut() {
        let result = Self.presentation(state: .init(), summary: SyncSummary(historyAgedOutDetected: true))
        #expect(result?.category == .historyAgedOut, "history aged out → ⑥ (informational)")
        #expect(result?.action == nil)
    }

    @Test
    func repositoryDamageMapsToRepositoryDamaged() {
        // Decryption failure / corrupt manifest / wrong vault / version
        // mismatch all present as repository-damaged.
        for damaged in [ProviderError.corrupt, .schemaUnsupported, .wrongVault, .tls] {
            let result = Self.presentation(state: .init(lastError: damaged))
            #expect(result?.category == .repositoryDamaged,
                    "\(damaged.sanitizedCode) → repositoryDamaged (⑦)")
            #expect(result?.action == .advancedRecovery)
        }
    }

    // MARK: - CHK002 multi-category priority

    @Test
    func multiCategoryPriorityIsDeterministic() {
        // plan.md §9: ⑦ repositoryDamaged > ③ needsUnlock > ② authFailed >
        // ① cannotConnect > ⑤ conflictCopies > ④ pendingChanges > ⑥ historyAgedOut.
        // Each test asserts the winner under a conflicting stack.
        func result(_ stack: SyncStatusInput) -> SyncStatusCategory? {
            Self.presentation(state: stack, summary: SyncSummary(
                historyAgedOutDetected: true,
                conflictCopiesCreated: 1
            ))?.category
        }

        // ⑦ beats everything.
        #expect(result(.init(lastError: .corrupt, vaultLocked: true)) == .repositoryDamaged)
        #expect(result(.init(lastError: .auth, vaultLocked: true)) == .needsUnlock,
                "③ needsUnlock beats ② authFailed")
        #expect(result(.init(lastError: .network, vaultLocked: true)) == .needsUnlock,
                "③ needsUnlock beats ① cannotConnect")
        #expect(result(.init(lastError: .auth)) == .authFailed,
                "② authFailed beats ① cannotConnect")
        #expect(result(.init(lastError: .network)) == .cannotConnect,
                "① cannotConnect beats ⑤ conflictCopies + ④ + ⑥")
        #expect(result(.init(hasOfflineChangesPending: true)) == .conflictCopiesCreated,
                "⑤ conflictCopies beats ④ pendingChanges + ⑥ (the helper always sets a conflict copy)")
        #expect(result(.init()) == .conflictCopiesCreated,
                "⑤ conflictCopies beats ⑥ historyAgedOut")
    }

    @Test
    func pendingChangesBeatsHistoryAgedOut() {
        // Without conflict copies: ④ pendingChanges > ⑥ historyAgedOut.
        let result = Self.presentation(
            state: .init(hasOfflineChangesPending: true),
            summary: SyncSummary(historyAgedOutDetected: true)
        )
        #expect(result?.category == .pendingChanges,
                "④ pendingChanges beats ⑥ historyAgedOut")
    }

    // MARK: - Localization + no-internal-identifier guards

    @Test
    func allCategoriesHaveCompleteLocalizations() {
        for category in SyncStatusCategory.allCases {
            let presentation = SyncStatusPresentation(
                category: category,
                title: String(localized: category.titleKey),
                detail: String(localized: category.detailKey),
                action: nil,
                isDismissible: category != .repositoryDamaged,
                symbolName: category.symbolName
            )
            #expect(!presentation.title.isEmpty, "\(category) title localized")
            #expect(!presentation.detail.isEmpty, "\(category) detail localized")
        }
    }

    @Test
    func userFacingTextHasNoInternalIdentifiers() {
        for category in SyncStatusCategory.allCases {
            let text = String(localized: category.titleKey) + " " + String(localized: category.detailKey)
            #expect(!text.contains("sync."), "no internal error identifiers (FR-011/SC-012)")
            #expect(!text.contains("ProviderError"), "no internal type names")
            #expect(!text.contains("://"), "no URLs")
        }
    }

    @Test
    func repositoryDamagedIsNotDismissible() {
        // FR-010: repository-damaged needs action, not dismissal.
        let result = Self.presentation(state: .init(lastError: .corrupt))
        #expect(result?.isDismissible == false)
    }
}

/// The sanitized input surface the mapping consumes (mirrors what the
/// coordinator exposes).
struct SyncStatusInput {
    var isConfigured = true
    var lastError: ProviderError?
    var vaultLocked = false
    var hasOfflineChangesPending = false
}
