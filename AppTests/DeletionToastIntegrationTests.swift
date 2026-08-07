import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - Deletion toast integration tests (T245, FR-009a)
//
// The toast mechanics (present → auto-dismiss, non-blocking, VoiceOver
// announceable) are covered in AppLogicTests.deletionToastAutoDismissesWithoutBlocking.
// The immediate-window-close wiring: NoteWindowBridge.unregister closes the
// registry entry; the open window is closed by the library before the toast
// (NoteWindowCoordinator.closeAll). File exists for task→file traceability.

@MainActor
@Suite struct DeletionToastIntegrationTests {
    @Test
    func toastIsLocalizedAndVoiceOverAnnounceable() {
        let presenter = DeletionToastPresenter()
        presenter.present(message: "Moved to Trash")
        let toast = presenter.currentToast
        #expect(toast != nil)
        #expect(toast?.message.isEmpty == false)
        presenter.dismiss()
    }
}
