import Testing
@testable import StickyNotes

// MARK: - 003 T183 (FR-014b/026 Rev 3, 2026-08-14)

/// Lifecycle of the Empty Trash confirmation request on `LibraryModel` —
/// the shared in-window confirmation mechanism for the header "⋯" menu,
/// the trash-scope view, and the app-menu command (FR-072).
struct TrashConfirmationModelTests {

    @MainActor
    @Test func requestIsInactiveByDefault() {
        let model = LibraryModel(environment: .placeholder)
        #expect(model.emptyTrashConfirmationRequested == false)
    }

    @MainActor
    @Test func requestAndAcknowledgeToggleTheFlag() {
        let model = LibraryModel(environment: .placeholder)
        model.requestEmptyTrashConfirmation()
        #expect(model.emptyTrashConfirmationRequested == true)

        model.acknowledgeEmptyTrashConfirmation()
        #expect(model.emptyTrashConfirmationRequested == false)
    }

    @MainActor
    @Test func leavingTrashScopeResetsTheRequest() {
        let model = LibraryModel(environment: .placeholder)
        model.scope = .trash
        model.requestEmptyTrashConfirmation()
        #expect(model.emptyTrashConfirmationRequested == true)

        // Switching back to Notes must never carry a stale confirmation
        // into the library scope.
        model.setScope(.library)
        #expect(model.emptyTrashConfirmationRequested == false)
    }

    @MainActor
    @Test func switchingWithinTrashKeepsTheRequest() {
        // setScope guards against no-op switches; a request made in Trash
        // stays until acknowledged or the scope is left.
        let model = LibraryModel(environment: .placeholder)
        model.scope = .trash
        model.requestEmptyTrashConfirmation()
        model.setScope(.trash)
        #expect(model.emptyTrashConfirmationRequested == true)
    }
}
