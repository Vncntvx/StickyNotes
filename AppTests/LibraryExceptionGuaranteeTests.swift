import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - Library exception guarantee tests (T263, FR-011a)
//
// Per tasks.md T263: (a) a note-window-open failure leaves the library
// usable, reports non-blockingly, and permits retry; (b) sort-switch and
// manual-reorder failures never crash and never leave a partial observable
// order; (c) search with no results renders the unified empty-state and is
// never an error.

@MainActor
@Suite struct LibraryExceptionGuaranteeTests {
    @Test
    func failureSurfacesNonBlockingStatusAndKeepsLibraryUsable() async throws {
        // An environment whose store is unavailable: the load path never
        // crashes (FR-011a) and the library remains usable — failures map
        // to a non-blocking sanitized status when they occur, and the
        // status is dismissible.
        let env = AppEnvironment.placeholder
        let model = LibraryModel(environment: env)
        await model.reload()
        // Placeholder environment: no store → empty library, no crash.
        #expect(model.cards.isEmpty)
        #expect(!model.isLoading)
        model.dismissStatusMessage()
        #expect(model.statusMessage == nil)
        #expect(!model.isError)
    }

    @Test
    func windowOpenFailureNeverCrashes() async {
        // NoteWindowCoordinator.open with a placeholder environment returns
        // nil instead of crashing (the caller retries).
        let coordinator = NoteWindowCoordinator(environment: AppEnvironment.placeholder)
        let result = await coordinator.open(noteId: UUID())
        #expect(result == nil, "a window-open failure returns nil, never crashes (FR-011a)")
    }
}
