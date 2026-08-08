import Foundation
import Persistence

// MARK: - WidgetNoteSelection (T306, FR-110/FR-111)
//
// App-side action behind the "small: one user-selected note" and "medium:
// todos from a selected note" widget forms (FR-110): persists the selected
// note id into the shared App Group store (`WidgetSelectionStore`, also
// read by the WidgetExtension) and triggers a change-driven reload of the
// two affected kinds (FR-110a). The FR-112 widget-eligibility filter still
// applies widget-side on top of this selection.

public enum WidgetNoteSelection {
    /// The widget kinds this selection affects.
    public static let affectedKinds: [WidgetRefreshCoordinator.Kind] = [.smallSelected, .mediumTodo]

    /// Sets (or clears, with `nil`) the note shown by the selected-note
    /// widget forms and refreshes their timelines.
    public static func setSelectedNote(_ id: UUID?) {
        WidgetSelectionStore.write(id)
        WidgetRefreshCoordinator.reload(affectedKinds)
    }

    /// The currently selected note id (nil when unset).
    public static func selectedNote() -> UUID? {
        WidgetSelectionStore.read()
    }
}
