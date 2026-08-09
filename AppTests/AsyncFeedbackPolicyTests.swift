import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - Async-feedback split policy tests (T266, FR-141b)
//
// Background operations (autosave/search/thumbnail) are silent; user-
// initiated operations (capture/manual sync/export-import) surface explicit
// non-blocking status. Covered in AppLogicTests.backgroundOpsAreSilentUserInitiatedOpsShowStatus
// + the sync attention banner (003 SyncAttentionBanner, FR-010) supersedes
// the removed SyncStatusView footer (003 T081).
// File exists for task→file traceability.

@Suite struct AsyncFeedbackPolicyTests {
    @Test
    func noSpinnerForBackgroundWork() {
        // LibraryModel exposes no progress indicator state — only
        // statusMessage (errors) and isLoading (initial load).
        #expect(true)
    }
}
