import Foundation

// MARK: - WidgetSelectionStore (T306, FR-110/FR-111)
//
// Device-local selection of the note shown by the "small: one user-selected
// note" and "medium: todos from a selected note" widget forms (FR-110).
// Lives in Persistence so BOTH the main app (writes via
// `WidgetNoteSelection`) and the WidgetExtension (reads at timeline
// generation) share the identical suite + key — the previous key lived
// privately in `WidgetExtension/StickyWidgetBundle.swift`, so the app had
// no way to write it and the selection could never be set.
//
// Device-local and never synchronized (like other App Group preferences);
// the widget still applies the FR-112 eligibility filter on top of this
// selection.

/// The shared selected-note store for the widget forms.
public enum WidgetSelectionStore {
    /// The App Group suite shared by app and widget.
    public static let suiteName = "group.local.stickynotes.placeholder"
    /// The persistence key for the selected note id.
    public static let key = "local.stickynotes.widget.selectedNoteId"

    public static func read() -> UUID? {
        guard let raw = UserDefaults(suiteName: suiteName)?.string(forKey: key) else { return nil }
        return UUID(uuidString: raw)
    }

    public static func write(_ id: UUID?) {
        UserDefaults(suiteName: suiteName)?.set(id?.uuidString, forKey: key)
    }
}
