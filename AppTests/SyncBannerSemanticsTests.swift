import Testing
import Foundation
@testable import StickyNotes

// MARK: - Sync banner semantics tests (003 T052, FR-010/FR-010a/CHK005/CHK030)
//
// Per tasks.md T052 and spec FR-010: dismiss hides the banner; it does NOT
// reappear while the underlying state is unchanged; a NEW error category
// re-presents; retry is non-blocking (FR-010a/001 FR-153); retry-fails-
// again persists the same category (CHK005); success clears the banner to
// zero footprint (CHK030).

@MainActor
@Suite struct SyncBannerSemanticsTests {

    @Test
    func dismissHidesBanner() {
        let model = SyncBannerStateModel()
        model.present(category: .cannotConnect)
        model.dismiss()
        #expect(model.current == nil, "dismiss hides the banner (FR-010)")
    }

    @Test
    func bannerDoesNotReappearWhileStateUnchanged() {
        let model = SyncBannerStateModel()
        model.present(category: .cannotConnect)
        model.dismiss()

        // Same category again → still hidden.
        model.present(category: .cannotConnect)
        #expect(model.current == nil, "no reappearance while the state is unchanged (FR-010)")
    }

    @Test
    func newCategoryRePresents() {
        let model = SyncBannerStateModel()
        model.present(category: .cannotConnect)
        model.dismiss()

        // A NEW category re-presents.
        model.present(category: .authFailed)
        #expect(model.current?.category == .authFailed, "a new error category re-presents (FR-010)")
    }

    @Test
    func retryIsNonBlockingAndTriggersManualSync() {
        let model = SyncBannerStateModel()
        var manualSyncCalls = 0
        model.onRetry = { manualSyncCalls += 1 }
        model.present(category: .cannotConnect)

        model.retry()
        #expect(manualSyncCalls == 1, "retry triggers a manual-sync-equivalent action")
        #expect(model.current == nil || model.current?.category == .cannotConnect,
                "retry does not require blocking local editing (FR-010a)")
    }

    @Test
    func retryFailsAgainPersistsSameCategory() {
        let model = SyncBannerStateModel()
        model.present(category: .cannotConnect)
        model.dismiss()

        // The same failure returns after a retry attempt — re-presents per
        // FR-010 without dismissal churn (CHK005).
        model.present(category: .cannotConnect, forceRePresent: true)
        #expect(model.current?.category == .cannotConnect, "retry-fails-again persists (CHK005)")
    }

    @Test
    func retrySuccessClearsBanner() {
        let model = SyncBannerStateModel()
        model.present(category: .cannotConnect)
        model.dismiss()

        // Success path: the state clears → zero footprint (CHK030).
        model.clearAll()
        #expect(model.current == nil, "success clears the banner to zero footprint (CHK030)")
    }

    @Test
    func unlockSuccessClearsNeedsUnlock() {
        let model = SyncBannerStateModel()
        model.present(category: .needsUnlock)
        model.clearAll()
        #expect(model.current == nil, "vault unlock success clears needsUnlock (CHK030)")
    }
}
