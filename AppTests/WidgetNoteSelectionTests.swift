import Testing
import Foundation
import Persistence
@testable import StickyNotes

// MARK: - FR-110 widget note selection (T306)
//
// Per tasks.md T306: the "small: one user-selected note" and "medium: todos
// from a selected note" widget forms MUST have a working selection path —
// `WidgetSelectionStore` round-trips the selection in the App Group
// defaults shared with the widget, and the app-side `WidgetNoteSelection`
// action persists the selection and triggers a change-driven reload of the
// affected kinds (FR-110a). Written FIRST and must FAIL before the
// implementation (Constitution XII).

@Suite("FR-110 widget note selection")
struct WidgetNoteSelectionTests {

    private static var suite: UserDefaults {
        UserDefaults(suiteName: WidgetSelectionStore.suiteName)!
    }

    @Test func storeRoundTripsSelection() {
        Self.suite.removeObject(forKey: WidgetSelectionStore.key)

        let id = UUID()
        WidgetSelectionStore.write(id)
        #expect(WidgetSelectionStore.read() == id)

        WidgetSelectionStore.write(nil)
        #expect(WidgetSelectionStore.read() == nil)
    }

    @Test func setSelectedNotePersistsAndReloadsAffectedKinds() {
        Self.suite.removeObject(forKey: WidgetSelectionStore.key)

        var reloaded: [WidgetRefreshCoordinator.Kind] = []
        WidgetRefreshCoordinator.reloadOverride = { reloaded = $0 }
        defer { WidgetRefreshCoordinator.reloadOverride = nil }

        let id = UUID()
        WidgetNoteSelection.setSelectedNote(id)
        #expect(WidgetSelectionStore.read() == id)
        #expect(reloaded == [.smallSelected, .mediumTodo])

        WidgetNoteSelection.setSelectedNote(nil)
        #expect(WidgetSelectionStore.read() == nil)
    }

    @Test func clearedStoreMeansNoSelectedNote() {
        Self.suite.removeObject(forKey: WidgetSelectionStore.key)
        #expect(WidgetSelectionStore.read() == nil)
    }
}
